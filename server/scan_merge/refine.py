"""Start from the user's layout (app convention), snap same-named spots together
with a small least-squares adjustment, report how far each join moved."""
import sys, json, numpy as np
from scipy.optimize import least_squares
user = json.load(open(sys.argv[1])); REF = "nus15"
anch = json.load(open("nus/anchors.json"))
rows = {r["map_slug"]: r for r in json.load(open("nus/rows.json"))}
scans = list(user)
def W(p, x, y, z):
    c, s = np.cos(p[0]), np.sin(p[0])
    return np.array([c*x - s*z + p[1], y + p[2], s*x + c*z + p[3]])
P0 = {s: np.array([user[s]["yaw"], user[s]["tx"], user[s]["ty"], user[s]["tz"]]) for s in scans}
spots = []  # (scan, id, name, local xyz)
for s in scans:
    for n in rows[s]["graph"]["pois"]:
        a = anch[s].get(n["id"])
        if a: spots.append((s, n["id"], n["name"].lower(), np.array([n["x"], a[1], n["z"]])))
def world(P, sp): return W(P[sp[0]], *sp[3])
same, near = [], []
for i, a in enumerate(spots):
    for b in spots[i+1:]:
        if a[0] == b[0]: continue
        d = np.linalg.norm((world(P0, a) - world(P0, b))[[0, 2]])
        if a[2] == b[2] and d < 8: same.append((a, b, d))
        elif d < 3: near.append((a, b, d))
# Heights: scans with no same-name join get their floor from route points that meet.
joined = {x[0][0] for x in same} | {x[1][0] for x in same}
free = [s for s in scans if s != REF]
idx = {s: i for i, s in enumerate(free)}
def unpack(v):
    P = {REF: P0[REF]}
    for s in free: P[s] = v[idx[s]*4: idx[s]*4+4]
    return P
def res(v):
    P = unpack(v); r = []
    for a, b, _ in same:
        d = world(P, a) - world(P, b); r += list(d[[0, 2]] / 0.1) + [d[1] / 0.15]
    for a, b, _ in near:
        d = world(P, a) - world(P, b); r += list(d[[0, 2]] / 1.5)
    for s in free:
        d = P[s] - P0[s]; r += [d[0] / np.radians(4), d[1] / 3, d[3] / 3, d[2] / 20]
    return np.array(r)
v0 = np.concatenate([P0[s] for s in free])
sol = least_squares(res, v0).x; P = unpack(sol)
print("same-name joins (planar gap in your layout -> after):")
for a, b, d in same:
    e = world(P, a) - world(P, b)
    print(f"  {a[0]}:{a[1]:20} = {b[0]}:{b[1]:20} {d:5.1f} m -> {np.linalg.norm(e[[0,2]]):.2f} m, height gap {e[1]:+.2f} m")
print("nearby route points used as weak joins:")
for a, b, d in near:
    e = world(P, a) - world(P, b)
    print(f"  {a[0]}:{a[1]:20} ~ {b[0]}:{b[1]:20} {d:4.1f} m -> {np.linalg.norm(e[[0,2]]):.2f} m, height gap {e[1]:+.2f}")
print("how much each scan moved from your layout:")
for s in free:
    d = P[s] - P0[s]; print(f"  {s:14} turn {np.degrees(d[0]):+5.1f}°  shift {np.hypot(d[1], d[3]):4.1f} m  height {d[2]:+.2f} m")
# to python pose convention for the merge/render tools
out = {}
for s in scans:
    y = -P[s][0]; c, sn = np.cos(y), np.sin(y)
    m = np.eye(4); m[:3, :3] = [[c, 0, sn], [0, 1, 0], [-sn, 0, c]]; m[:3, 3] = [P[s][1], P[s][2], P[s][3]]
    out[s] = m.tolist()
json.dump(out, open("nus/poses.json", "w"))
json.dump([[f"{a[0]}/{a[1]}", f"{b[0]}/{b[1]}"] for a, b, _ in same], open("nus/same_pairs.json", "w"))
print("heights of places:")
for sp in spots:
    n = next(q for q in rows[sp[0]]["graph"]["pois"] if q["id"] == sp[1])
    if n["category"] != "junction": print(f"  {sp[0]:13} {n['name']:20} {world(P, sp)[1]:+.2f}")
