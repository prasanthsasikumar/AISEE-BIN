"""Register each Immersal sparse cloud onto its own ARKit scan cloud (yaw + xyz)."""
import numpy as np, json, sys
from scipy.spatial import cKDTree
sys.path.insert(0, "nustools")
from immframe import ply, rows
def rot(y):  # app convention: x' = c x - s z ; z' = s x + c z
    c, s = np.cos(y), np.sin(y); return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])
G = 0.25
def grid(P, lo, n=512):
    ij = np.floor((P[:, [0, 2]] - lo) / G).astype(int); ok = np.all((ij >= 0) & (ij < n), 1)
    g = np.zeros((n, n), np.float32); g[ij[ok, 0], ij[ok, 1]] = 1; return g
out = {}
for s in [f"nus{i}" for i in range(2, 16)]:
    mid = rows[s]["graph"]["immersalAlignment"]["mapIDs"][0]
    I = ply(f"nus/imm/{mid}.ply"); A = np.load(f"nus/{s}.npy").astype(np.float64)
    lo_, hi_ = np.percentile(A, 1, 0), np.percentile(A, 99, 0); A = A[np.all((A > lo_ - 2) & (A < hi_ + 2), 1)]
    lo_, hi_ = np.percentile(I, 1, 0), np.percentile(I, 99, 0); I = I[np.all((I > lo_ - 2) & (I < hi_ + 2), 1)]
    tree = cKDTree(A)
    Is = I[np.random.default_rng(0).choice(len(I), min(len(I), 3000), replace=False)]
    la = A[:, [0, 2]].min(0) - 2; FA = np.fft.rfft2(grid(A, la), s=(1024, 1024))
    best = None
    for deg in range(0, 360, 2):
        R = rot(np.radians(deg)); B = Is @ R.T; lb = B[:, [0, 2]].min(0)
        gb = grid(B, lb); c = np.fft.irfft2(FA * np.conj(np.fft.rfft2(gb, s=(1024, 1024))), s=(1024, 1024))
        i, j = np.unravel_index(np.argmax(c), c.shape); i -= 1024 * (i > 512); j -= 1024 * (j > 512)
        sh = la + np.array([i, j]) * G - lb; t = np.array([sh[0], 0, sh[1]])
        d, k = tree.query(B + t, distance_upper_bound=0.5); m = np.isfinite(d)
        if m.sum() > 20: t[1] = np.median(A[k[m], 1] - (B[m, 1]))
        d, _ = tree.query(B + t, distance_upper_bound=0.2); sc = np.isfinite(d).mean()
        if best is None or sc > best[0]: best = (sc, np.radians(deg), t)
    sc, yaw, t = best
    # ICP refine
    for it in range(30):
        B = Is @ rot(yaw).T + t; d, k = tree.query(B, distance_upper_bound=max(0.15, 0.6 * 0.9 ** it)); m = np.isfinite(d)
        P, Q = Is[m], A[k[m]]; pc, qc = P.mean(0), Q.mean(0); P0, Q0 = P - pc, Q - qc
        yaw = np.arctan2((P0[:, 0] * Q0[:, 2] - P0[:, 2] * Q0[:, 0]).sum(), (P0[:, 0] * Q0[:, 0] + P0[:, 2] * Q0[:, 2]).sum())
        t = qc - pc @ rot(yaw).T
    d, _ = tree.query(Is @ rot(yaw).T + t, distance_upper_bound=0.15); fit = np.isfinite(d).mean()
    out[s] = {"mapID": mid, "yaw": float(yaw), "t": t.tolist(), "fit": float(fit)}
    print(f"{s:6} {mid}  yaw {np.degrees(yaw):7.1f}°  t {np.round(t, 2)}  coarse {sc:.2f}  fit {fit:.2f}", flush=True)
json.dump(out, open("nus/imm_to_scan.json", "w"), indent=1)
