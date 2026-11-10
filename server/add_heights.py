#!/usr/bin/env python3
"""Publish a new version of a map with each place's height (`y`) read from its
ARWorldMap anchors, for scans made before Author recorded heights (build 16 and
earlier). NUS Open House Guide uses the heights to tell floors apart.

    python3 server/add_heights.py <slug>            # dry run: prints heights and levels
    python3 server/add_heights.py <slug> --publish  # inserts version n+1 (source "web")

Uses only the publishable key, like the web editor. Places without an anchor
(waypoints, places added in the editor) are left without `y`; the app fills them
from their neighbours.
"""
import gzip, json, plistlib, struct, sys, urllib.request

BASE = "https://djfpemdkeguztyuerxqc.supabase.co"
KEY = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"
HEAD = {"apikey": KEY, "Authorization": "Bearer " + KEY}


def call(path, body=None, method=None, extra=None):
    req = urllib.request.Request(BASE + path, method=method or ("POST" if body is not None else "GET"),
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={**HEAD, "Content-Type": "application/json", **(extra or {})})
    with urllib.request.urlopen(req) as r:
        return r.read()


def anchors(worldmap: bytes) -> dict:
    if worldmap[:2] == b"\x1f\x8b":
        worldmap = gzip.decompress(worldmap)
    objs = plistlib.loads(worldmap)["$objects"]
    out = {}
    for o in objs:
        if not isinstance(o, dict) or "transform" not in o or "name" not in o:
            continue
        name = objs[o["name"].data]
        if isinstance(name, str) and name.startswith("poi:"):
            f = struct.unpack("<16f", o["transform"])
            out[name[4:]] = (f[12], f[13], f[14])
    return out


def main():
    slug, publish = sys.argv[1], "--publish" in sys.argv
    rows = json.loads(call(f"/rest/v1/ab_map_versions?map_slug=eq.{slug}&order=version.desc&limit=1"))
    if not rows:
        sys.exit(f"no map called {slug}")
    row = rows[0]
    if not row.get("worldmap_path"):
        sys.exit("this version has no ARKit world map, so there are no anchors to read")
    wm = call(f"/storage/v1/object/public/aiseebin-maps/{row['worldmap_path']}")
    found = anchors(wm)
    graph = row["graph"]
    n = 0
    for p in graph["pois"]:
        a = found.get(p["id"])
        if a:
            p["y"] = round(a[1], 3)
            n += 1
        print(f"{p['id']:30} {p.get('category','destination'):12} y={p.get('y')}")
    ys = sorted(p["y"] for p in graph["pois"] if "y" in p)
    levels, group = [], ys[:1]
    for v in ys[1:]:
        if v - group[-1] > 2.0:
            levels.append(sum(group) / len(group)); group = [v]
        else:
            group.append(v)
    if group:
        levels.append(sum(group) / len(group))
    print(f"\nv{row['version']}: {n}/{len(graph['pois'])} places got a height; levels at {[round(l, 2) for l in levels]}")
    if not publish:
        print("dry run; add --publish to save a new version")
        return
    version = json.loads(call("/rest/v1/rpc/ab_next_version", {"slug": slug}))
    new = {"map_slug": slug, "version": version, "source": "web", "note": "heights from world-map anchors",
           "graph": graph, "worldmap_path": row["worldmap_path"], "pointcloud_path": row.get("pointcloud_path"),
           "point_count": row.get("point_count")}
    call("/rest/v1/ab_map_versions", new, extra={"Prefer": "return=minimal"})
    print(f"published {slug} v{version}")


if __name__ == "__main__":
    main()
