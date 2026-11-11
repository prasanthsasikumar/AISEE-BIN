"""Is each Immersal map in the same frame as its ARKit scan? Compare the clouds."""
import numpy as np, json, sys
from scipy.spatial import cKDTree
def ply(path):
    b = open(path, "rb").read(); h = b.index(b"end_header\n") + 11
    head = b[:h].decode(); n = int(head.split("element vertex ")[1].split()[0])
    rgb = "property uchar red" in head; st = 15 if rgb else 12
    dt = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4")] + ([("r", "u1"), ("g", "u1"), ("b", "u1")] if rgb else []))
    a = np.frombuffer(b[h:h + n * st], dtype=dt); return np.stack([a["x"], a["y"], a["z"]], 1).astype(np.float64)
rows = {r["map_slug"]: r for r in json.load(open("nus/rows.json"))}
def score(A, B, thr=0.15):
    d, _ = cKDTree(A).query(B, distance_upper_bound=thr); return np.isfinite(d).mean()
for s in [f"nus{i}" for i in range(2, 16)]:
    mid = rows[s]["graph"]["immersalAlignment"]["mapIDs"][0]
    I = ply(f"nus/imm/{mid}.ply"); A = np.load(f"nus/{s}.npy").astype(np.float64)
    A = A[np.random.default_rng(0).choice(len(A), min(len(A), 20000), replace=False)]
    I = I[np.random.default_rng(0).choice(len(I), min(len(I), 6000), replace=False)]
    cand = {"same": I, "z flipped": I * [1, 1, -1], "x flipped": I * [-1, 1, 1], "x,z flipped": I * [-1, 1, -1], "y,z flipped": I * [1, -1, -1]}
    res = {k: round(score(A, v), 3) for k, v in cand.items()}
    print(s, mid, "immersal centre", I.mean(0).round(1), "arkit centre", A.mean(0).round(1), res)
