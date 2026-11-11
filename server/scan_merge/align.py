"""Compose scans into one frame from pairwise links, refine each link with local
4-DOF ICP, and render a top-down PNG."""
import numpy as np, json, sys
from scipy.spatial import cKDTree
from PIL import Image, ImageDraw
D = sys.argv[1]
anch = json.load(open(f"{D}/anchors.json"))
rows = {r["map_slug"]: r for r in json.load(open(f"{D}/rows.json"))}
def load(s):
    p = np.load(f"{D}/{s}.npy").astype(np.float64)
    lo, hi = np.percentile(p, 1, 0), np.percentile(p, 99, 0)
    return p[np.all((p >= lo - 2) & (p <= hi + 2), 1)]
def rot(yaw):
    c, s = np.cos(yaw), np.sin(yaw)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def M(yaw, t):
    m = np.eye(4); m[:3, :3] = rot(yaw); m[:3, 3] = t; return m
def apply(m, p): return p @ m[:3, :3].T + m[:3, 3]
def yaw_of(m): return np.arctan2(m[0, 2], m[0, 0])

def icp_local(A, B, m, center, R=15, iters=25):
    """Refine m (B->A) using A points near center (A frame)."""
    A0 = A[np.linalg.norm(A[:, [0, 2]] - center[[0, 2]], axis=1) < R + 3]
    tree = cKDTree(A0)
    yaw, t = yaw_of(m), m[:3, 3].copy()
    Bl = B[np.linalg.norm(apply(m, B)[:, [0, 2]] - center[[0, 2]], axis=1) < R]
    thr = 0.5
    for _ in range(iters):
        Bt = Bl @ rot(yaw).T + t
        d, idx = tree.query(Bt, distance_upper_bound=thr)
        k = np.isfinite(d)
        if k.sum() < 50: break
        P, Q = Bl[k], A0[idx[k]]
        pc, qc = P.mean(0), Q.mean(0); P0, Q0 = P - pc, Q - qc
        yaw = np.arctan2((P0[:, 2] * Q0[:, 0] - P0[:, 0] * Q0[:, 2]).sum(), (P0[:, 0] * Q0[:, 0] + P0[:, 2] * Q0[:, 2]).sum())
        t = qc - pc @ rot(yaw).T
        thr = max(0.2, thr * 0.85)
    d, _ = tree.query(Bl @ rot(yaw).T + t, distance_upper_bound=0.2)
    return M(yaw, t), float(np.isfinite(d).mean())

def link_from_seed(a, b, na, nb, deg):
    pa, pb = np.array(anch[a][na]), np.array(anch[b][nb])
    r = rot(np.radians(deg))
    return M(np.radians(deg), pa - r @ pb), pa

def link_two(a, b, names):
    """Exact 2-point (planar) fit from two shared spots, height from the first."""
    P = np.array([anch[b][n] for n in names]); Q = np.array([anch[a][n] for n in names])
    vb, va = P[1] - P[0], Q[1] - Q[0]
    # rot(yaw) maps (x,z): x' = c x + s z ; z' = -s x + c z  -> angle in (x,z) plane decreases by yaw
    yaw = np.arctan2(vb[1 * 0 + 2], vb[0]) - np.arctan2(va[2], va[0])
    r = rot(yaw)
    return M(yaw, Q[0] - r @ P[0]), Q[0]

if __name__ == "__main__":
    spec = json.load(open(sys.argv[2]))
    pts = {s: load(s) for s in rows}
    pose = {spec["root"]: np.eye(4)}
    report = []
    pending = list(spec["links"])
    while pending:
        progressed = False
        for L in list(pending):
            a, b = L["a"], L["b"]
            if a in pose and b not in pose:
                pass
            elif b in pose and a not in pose:
                # invert link direction by swapping roles below
                pass
            else:
                continue
            if "two" in L: m, c = link_two(a, b, L["two"])
            else: m, c = link_from_seed(a, b, L["na"], L.get("nb", L["na"]), L["yaw"])
            fit0 = None
            if L.get("icp", True):
                m2, fit = icp_local(pts[a], pts[b], m, c)
                moved = np.linalg.norm(m2[:3, 3] - m[:3, 3]); dyaw = np.degrees(yaw_of(m2) - yaw_of(m))
                _, fit0 = icp_local(pts[a], pts[b], m, c, iters=0)
                if abs(dyaw) < 15 and moved < 3: m = m2
            else: fit = None
            if a in pose: pose[b] = pose[a] @ m
            else: pose[a] = pose[b] @ np.linalg.inv(m)
            report.append(f"{a}<-{b}: yaw {np.degrees(yaw_of(m)):.1f} fit0 {fit0} fit {fit}")
            pending.remove(L); progressed = True
        if not progressed: break
    print("\n".join(report)); print("unplaced:", [s for s in rows if s not in pose])
    json.dump({s: m.tolist() for s, m in pose.items()}, open(f"{D}/poses.json", "w"))
    # render
    allp = np.vstack([apply(pose[s], pts[s]) for s in pose])
    lo, hi = np.percentile(allp, 0.5, 0), np.percentile(allp, 99.5, 0)
    S = 10; W, H = int((hi[0] - lo[0]) * S) + 40, int((hi[2] - lo[2]) * S) + 40
    img = Image.new("RGB", (W, H), "white"); dr = ImageDraw.Draw(img)
    pal = [(230,25,75),(60,180,75),(0,130,200),(245,130,48),(145,30,180),(70,240,240),(240,50,230),(210,245,60),(250,190,212),(0,128,128),(170,110,40),(128,0,0),(128,128,0),(0,0,128),(128,128,128)]
    X = lambda p: (20 + (p[0] - lo[0]) * S, 20 + (p[2] - lo[2]) * S)
    for i, s in enumerate(rows):
        if s not in pose: continue
        col = pal[i % len(pal)]
        P = apply(pose[s], pts[s])
        P = P[np.random.default_rng(0).choice(len(P), min(len(P), 6000), replace=False)]
        for p in P:
            x, y = X(p); dr.point((x, y), fill=col)
        g = rows[s]["graph"]; ids = {}
        for q in g["pois"]:
            a = anch[s].get(q["id"]); yv = a[1] if a else 0
            w = apply(pose[s], np.array([[q["x"], yv, q["z"]]]))[0]; ids[q["id"]] = w
        for e in g["edges"]:
            dr.line([X(ids[e["from"]]), X(ids[e["to"]])], fill=col, width=3)
        for q in g["pois"]:
            if q["category"] != "junction" or not q["id"].startswith("wp"):
                x, y = X(ids[q["id"]]); dr.ellipse([x-5,y-5,x+5,y+5], fill=col, outline="black")
                dr.text((x+7, y-7), f"{s}:{q['name']}", fill="black")
    img.save(f"{D}/{spec.get('out','top.png')}")
    print(img.size)
