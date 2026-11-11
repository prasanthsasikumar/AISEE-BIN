"""Yaw search around a shared named spot: B's spot is pinned onto A's spot,
yaw swept 0..359, scored by 3D nearest-neighbour agreement near the spot."""
import numpy as np, json, sys
from scipy.spatial import cKDTree
D = sys.argv[1]
anch = json.load(open(f"{D}/anchors.json"))
def load(s):
    p = np.load(f"{D}/{s}.npy").astype(np.float64)
    lo, hi = np.percentile(p, 1, 0), np.percentile(p, 99, 0)
    return p[np.all((p >= lo - 2) & (p <= hi + 2), 1)]
def rot(yaw):
    c, s = np.cos(yaw), np.sin(yaw)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def sweep(a, b, na, nb, R=12, thr=0.2):
    A, B = load(a), load(b)
    pa, pb = np.array(anch[a][na]), np.array(anch[b][nb])
    A0 = A[np.linalg.norm(A[:, [0, 2]] - pa[[0, 2]], axis=1) < R + 3]
    B0 = B[np.linalg.norm(B[:, [0, 2]] - pb[[0, 2]], axis=1) < R] - pb
    tree = cKDTree(A0)
    scores = []
    for deg in range(360):
        Bt = B0 @ rot(np.radians(deg)).T + pa
        d, _ = tree.query(Bt, distance_upper_bound=thr)
        scores.append(np.isfinite(d).mean())
    scores = np.array(scores)
    best = int(scores.argmax())
    # second peak at least 20 deg away
    mask = np.abs(((np.arange(360) - best + 180) % 360) - 180) > 20
    second = scores[mask].max()
    return best, scores[best], second, len(A0), len(B0)
for spec in sys.argv[2:]:
    a, b, na, nb = (spec.split(":") + [None])[:4]
    nb = nb or na
    best, s1, s2, nA, nB = sweep(a, b, na, nb)
    print(f"{a}:{na} <- {b}:{nb}  yaw={best:4d}  score={s1:.3f}  next={s2:.3f}  ratio={s1/max(s2,1e-6):.2f}  nA={nA} nB={nB}")
