"""Place every Immersal map from a calibration walk: fixes from two maps a few
seconds apart in one ARKit session give one map's pose in the other's frame.

    python3 calibrate.py <since ISO time> [--write]
Reads loc.attempt events (map_pose, session_pose) from the server, solves all
map placements with nus15 held at its current (v6) placement, prints the
residuals per pair, and with --write saves nus/poses.json (scan placements)."""
import json, sys, math, urllib.request, collections, itertools
import numpy as np
from scipy.optimize import least_squares
since = sys.argv[1]; WRITE = "--write" in sys.argv
B = "https://djfpemdkeguztyuerxqc.supabase.co"; K = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"; H = {"apikey": K, "Authorization": "Bearer " + K}
get = lambda p: json.load(urllib.request.urlopen(urllib.request.Request(B + p, headers=H)))
rows = {r["map_slug"]: r for r in json.load(open("nus/rows.json"))}
IMM = json.load(open("nus/imm_to_scan.json"))
id2scan = {v["mapID"]: s for s, v in IMM.items()}
v6 = get("/rest/v1/ab_map_versions?map_slug=eq.nus-com&order=version.desc&limit=1&select=graph,version")[0]
place0 = {m["id"]: m for m in v6["graph"]["immersalAlignment"]["maps"]}
print("current nus-com version", v6["version"])

def R(y): c, s = math.cos(y), math.sin(y); return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])  # app: x' = c x - s z
def Tm(y, t): m = np.eye(4); m[:3, :3] = R(y); m[:3, 3] = t; return m
def yaw_of(m): return math.atan2(m[2, 0], m[0, 0])

fixes = []
def events(sid):
    off = 0
    while True:
        page = get(f"/rest/v1/ab_events?session_id=eq.{sid}&type=eq.loc.attempt&order=seq.asc&limit=1000&offset={off}")
        yield from page; off += len(page)
        if len(page) < 1000: return
for s in get(f"/rest/v1/ab_sessions?select=session_id&started_at=gte.{since}&app=eq.nus-open-house&device=like.iPhone*"):
    for e in events(s["session_id"]):
        d = e["data"]
        if not d.get("ok") or not d.get("map_pose") or not d.get("session_pose"): continue
        mp, sp = d["map_pose"], d["session_pose"]
        yaw = mp[3] - sp[3]                         # session -> map
        t = np.array(mp[:3]) - R(yaw) @ np.array(sp[:3])
        fixes.append(dict(sid=s["session_id"], t=np.datetime64(e["t"].split("+")[0].rstrip("Z")), map=d["map_id"], T=Tm(yaw, t), sp=np.array(sp[:3])))
print(len(fixes), "fixes with poses;", dict(collections.Counter(id2scan.get(f["map"], f["map"]) for f in fixes)))
if not fixes: sys.exit("no fixes with poses yet: walk with build 4 first")
# Drop matches nothing confirms: a real match agrees (same session->map transform,
# within 2 m and 10 deg at the camera) with another match from the same map within 60 s.
def agree(f, g):
    d = f["T"] @ np.r_[f["sp"], 1] - g["T"] @ np.r_[f["sp"], 1]
    dy = abs((yaw_of(f["T"]) - yaw_of(g["T"]) + math.pi) % (2 * math.pi) - math.pi)
    return np.linalg.norm(d[:3]) < 2.0 and math.degrees(dy) < 10
kept = [f for f in fixes if any(g is not f and g["map"] == f["map"] and g["sid"] == f["sid"]
        and abs((g["t"] - f["t"]) / np.timedelta64(1, "s")) < 60 and agree(f, g) for g in fixes)]
dropped = collections.Counter(id2scan.get(f["map"]) for f in fixes if not any(f is k for k in kept))
print("dropped unconfirmed matches:", dict(dropped)); fixes = kept
# within-map self-consistency (how good is a single fix)
# pairs across maps within 20 s in the same session
pairs = []
for a, b in itertools.combinations(fixes, 2):
    if a["sid"] != b["sid"] or a["map"] == b["map"]: continue
    if abs((a["t"] - b["t"]) / np.timedelta64(1, "s")) > 20: continue
    T_ab = a["T"] @ np.linalg.inv(b["T"])     # b-map coords -> a-map coords
    pairs.append((a["map"], b["map"], T_ab, b["T"] @ np.r_[b["sp"], 1]))
EXCL = {tuple(sorted(x.split("-"))) for x in sys.argv[2:] if "-" in x and not x.startswith("--")}
allpairs = pairs
pairs = [p for p in pairs if tuple(sorted((id2scan[p[0]], id2scan[p[1]]))) not in EXCL]
print("excluded pairs:", sorted(EXCL))
links = collections.Counter(tuple(sorted((id2scan[a], id2scan[b]))) for a, b, _, _ in pairs)
print("map pairs seen together:", dict(links))
maps = sorted({f["map"] for f in fixes}); ref = IMM["nus15"]["mapID"]
free = [m for m in maps if m != ref]; ix = {m: i for i, m in enumerate(free)}
P0 = {m: Tm(place0[m]["yaw"], [place0[m]["tx"], place0[m].get("ty", 0), place0[m]["tz"]]) for m in place0}
def P(v, m):
    if m == ref or m not in ix: return P0[m]
    y, x, yy, z = v[ix[m] * 4: ix[m] * 4 + 4]; return Tm(y, [x, yy, z])
def res(v):
    r = []
    for a, b, T_ab, q in pairs:
        if a not in maps or b not in maps: continue
        pa = P(v, a) @ T_ab @ q; pb = P(v, b) @ q        # where the same point lands via a and via b
        r += list(pa[:3] - pb[:3])
    return np.array(r)
v0 = np.concatenate([[yaw_of(P0[m]), *P0[m][:3, 3]] for m in free]) if free else np.zeros(0)
sol = least_squares(res, v0, loss="soft_l1", f_scale=1.0)
v = sol.x
per = collections.defaultdict(list)
for a, b, T_ab, q in allpairs:
    pa = P(v, a) @ T_ab @ q; pb = P(v, b) @ q; p0a = P0[a] @ T_ab @ q; p0b = P0[b] @ q
    per[tuple(sorted((id2scan[a], id2scan[b])))].append((np.linalg.norm(pa[:3] - pb[:3]), np.linalg.norm(p0a[:3] - p0b[:3])))
print("pair: disagreement before -> after (median m, n)")
for k, l in sorted(per.items()): print(f"  {k[0]:6}-{k[1]:6} {np.median([x[1] for x in l]):6.1f} -> {np.median([x[0] for x in l]):5.2f}   n={len(l)}")
print("moved from v6:")
for m in free:
    d = np.linalg.inv(P0[m]) @ P(v, m); print(f"  {id2scan[m]:6} turn {math.degrees(yaw_of(d)):+7.1f}°  shift {np.linalg.norm(P(v, m)[[0, 2], 3] - P0[m][[0, 2], 3]):5.1f} m  height {P(v, m)[1, 3] - P0[m][1, 3]:+.2f}")
if WRITE:
    # scan placement = immersal placement ∘ (immersal -> scan)^-1, written in align.py's convention (python yaw = -app yaw)
    poses = json.load(open("nus/poses.json"))
    for m in maps:
        s = id2scan[m]; i2s = Tm(IMM[s]["yaw"], IMM[s]["t"]); S = P(v, m) @ np.linalg.inv(i2s)
        yp = -yaw_of(S); c, sn = math.cos(yp), math.sin(yp); M = np.eye(4); M[:3, :3] = [[c, 0, sn], [0, 1, 0], [-sn, 0, c]]; M[:3, 3] = S[:3, 3]
        poses[s] = M.tolist()
    json.dump(poses, open("nus/poses.json", "w")); print("wrote nus/poses.json for", [id2scan[m] for m in maps])
