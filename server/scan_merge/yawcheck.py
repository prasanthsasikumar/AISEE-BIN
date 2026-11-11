import numpy as np, json, sys
from scipy.spatial import cKDTree
import io, contextlib
with contextlib.redirect_stdout(io.StringIO()):
    sys.path.insert(0, "nustools"); from immframe import ply, rows
def rot(y): c, s = np.cos(y), np.sin(y); return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])
cur = json.load(open("nus/imm_to_scan.json"))
for s in sys.argv[1:]:
    mid = rows[s]["graph"]["immersalAlignment"]["mapIDs"][0]
    I = ply(f"nus/imm/{mid}.ply"); A = np.load(f"nus/{s}.npy").astype(np.float64)
    tree = cKDTree(A); Is = I[np.random.default_rng(1).choice(len(I), min(len(I), 4000), replace=False)]
    sc = []
    for d in range(360):  # translation fixed at 0 (shared origin), vertical too
        dd, _ = tree.query(Is @ rot(np.radians(d)).T, distance_upper_bound=0.2); sc.append(np.isfinite(dd).mean())
    sc = np.array(sc); top = np.argsort(sc)[::-1]
    peaks = []
    for i in top:
        if all(min(abs(i - p), 360 - abs(i - p)) > 15 for p in peaks): peaks.append(i)
        if len(peaks) == 3: break
    print(s, mid, "current", round(np.degrees(cur[s]["yaw"]) % 360, 1), "peaks (yaw: score)", [(int(p), round(sc[p], 3)) for p in peaks], "median", round(np.median(sc), 3))
