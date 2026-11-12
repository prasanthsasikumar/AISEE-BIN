"""Build one combined graph + Immersal multi-map alignment from placed scans."""
import numpy as np, json, sys, math
sys.path.insert(0, sys.path[0])
from align import apply, rows, anch, yaw_of
D, spec_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
spec = json.load(open(spec_path))
IMM = json.load(open(f"{D}/imm_to_scan.json"))
pose = {k: np.array(v) for k, v in json.load(open(f"{D}/poses.json")).items()}
same = spec.get("same", [])          # [["nus2/makan","nus3/makan"], ...] first one kept
rename = spec.get("rename", {})      # id -> new display name
drop_maps = set(spec.get("drop", []))
alias = {}
for group in same:
    for g in group[1:]: alias[g] = group[0]
pois, edges, seen = [], set(), {}
placements = []
scan_heights = {}   # scan -> ({local id: graph y of a marked place}, [(local a, local b)])
for s in rows:
    if s not in pose or s in drop_maps: continue
    m = pose[s]
    al = rows[s]["graph"].get("immersalAlignment")
    if al:
        # python rot() is the app's yaw negated; app: x' = c x - s z + tx
        # The Immersal map is the scan turned by imm["yaw"] about the scan's origin (plus a tiny
        # offset): compose scan->graph with immersal->scan. App convention: x' = c x - s z + tx.
        imm = IMM[s]; ys = float(-yaw_of(m)); c, sn = math.cos(ys), math.sin(ys)
        ti = imm["t"]
        placements.append({"id": al["mapIDs"][0], "yaw": ys + imm["yaw"],
                           "tx": float(m[0, 3]) + c * ti[0] - sn * ti[2], "ty": float(m[1, 3]) + ti[1],
                           "tz": float(m[2, 3]) + sn * ti[0] + c * ti[2], "name": s})
    known = {}
    for q in rows[s]["graph"]["pois"]:
        gid = f"{s}/{q['id']}"
        a = anch[s].get(q["id"])
        w = apply(m, np.array([[q["x"], a[1] if a else 0.0, q["z"]]]))[0]
        if a: known[q["id"]] = float(w[1])
        if gid in alias: continue
        p = dict(q); p["id"] = gid; p["x"] = round(float(w[0]), 3); p["z"] = round(float(w[2]), 3)
        if a: p["y"] = round(float(w[1]), 3)
        else: p.pop("y", None)
        p["name"] = rename.get(gid, q["name"])
        if p["category"] == "junction" and p["name"].startswith("Waypoint"):
            p["name"] = f"{s} {p['name']}"   # unique, never shown to visitors
        pois.append(p)
    for e in rows[s]["graph"]["edges"]:
        a, b = alias.get(f"{s}/{e['from']}", f"{s}/{e['from']}"), alias.get(f"{s}/{e['to']}", f"{s}/{e['to']}")
        if a != b: edges.add(tuple(sorted((a, b))))
    scan_heights[s] = (known, [(e["from"], e["to"]) for e in rows[s]["graph"]["edges"]])
for n in spec.get("extra_nodes", []): pois.append(dict(n, aliases=[], details=None))
for a, b in spec.get("extra_edges", []): edges.add(tuple(sorted((a, b))))
hy = {p["id"]: p["y"] for p in pois if "y" in p}
# Waypoints carry no height. Within each scan, a waypoint takes the height of the nearest
# marked place by hops along that scan's own route (as the app does). Doing it per scan
# keeps a scan that climbs stairs upstairs at its far end: nus2 walks Water -> stairs ->
# MPH 2, and filling across the merged graph (12 Nov) put its upper corridor on the ground
# floor, so the join below linked it flat to the ground-floor Junction (v8 bug).
for s, (known, ledges) in scan_heights.items():
    nbl = {}
    for a, b in ledges: nbl.setdefault(a, []).append(b); nbl.setdefault(b, []).append(a)
    fill, frontier = dict(known), list(known)
    while frontier:
        nxt = []
        for i in frontier:
            for o in nbl.get(i, []):
                if o not in fill: fill[o] = fill[i]; nxt.append(o)
        frontier = nxt
    for lid, y in fill.items(): hy.setdefault(alias.get(f"{s}/{lid}", f"{s}/{lid}"), y)
# Scans with no marked place at all: average of neighbours across scans.
nb = {}
for a, b in edges: nb.setdefault(a, []).append(b); nb.setdefault(b, []).append(a)
grew = True
while grew:
    grew = False
    for p in pois:
        if p["id"] in hy: continue
        ys = [hy[n] for n in nb.get(p["id"], []) if n in hy]
        if ys: hy[p["id"]] = sum(ys) / len(ys); grew = True
# Join scans where their route points meet: nearest pair from different scans within 2.5 m, same floor.
scan_of = lambda i: i.split("/")[0]
for i, p in enumerate(pois):
    for q in pois[i + 1:]:
        if scan_of(p["id"]) == scan_of(q["id"]): continue
        if abs(hy.get(p["id"], 0) - hy.get(q["id"], 0)) > 1.5: continue
        if ((p["x"] - q["x"]) ** 2 + (p["z"] - q["z"]) ** 2) ** 0.5 < 2.5: edges.add(tuple(sorted((p["id"], q["id"]))))
# Give every waypoint its height so the app sees the same floors (stairs inside a scan
# become a level change it can announce), and flag any link between scans that jumps a floor.
for p in pois:
    if "y" not in p and p["id"] in hy: p["y"] = round(float(hy[p["id"]]), 3)
for a, b in sorted(edges):
    if scan_of(a) != scan_of(b) and a in hy and b in hy and abs(hy[a] - hy[b]) > 2.0:
        print(f"WARNING: {a} ({hy[a]:.1f}) <-> {b} ({hy[b]:.1f}) joins two floors with no stairs")
ids = {p["id"] for p in pois}
bad = [e for e in edges if e[0] not in ids or e[1] not in ids]
assert not bad, bad
mo = spec.get("map_order")
if mo: placements.sort(key=lambda m: mo.index(m["name"]))
order = spec.get("order", [])
pois.sort(key=lambda p: order.index(p["id"]) if p["id"] in order else len(order))
first = placements[0]
graph = {"name": spec["name"], "tourStart": spec.get("tourStart"), "pois": pois, "edges": [{"from": a, "to": b} for a, b in sorted(edges)],
         "immersalAlignment": {"mapIDs": [p["id"] for p in placements], "yaw": first["yaw"], "tx": first["tx"],
                               "tz": first["tz"], "pairCount": 0, "rmsError": 0,
                               "maps": placements}}
json.dump(graph, open(out_path, "w"), indent=1)
ys = sorted(p["y"] for p in pois if "y" in p)
print(len(pois), "nodes", len(edges), "edges", len(placements), "maps")
print("heights:", [round(y, 1) for y in ys])
for p in pois:
    if p["category"] not in ("junction",): print(f"  {p['id']:28} {p['category']:12} {p['name']:20} y={p.get('y')}")
