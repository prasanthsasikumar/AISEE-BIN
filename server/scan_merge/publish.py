import sys, json, gzip, urllib.request, numpy as np
slug = sys.argv[1]; sys.argv = [sys.argv[0], "nus"]; sys.path.insert(0, "nustools")
from align import load, apply
BASE = "https://djfpemdkeguztyuerxqc.supabase.co"; KEY = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"
H = {"apikey": KEY, "Authorization": "Bearer " + KEY}
def call(path, body=None, ctype="application/json", extra=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    r = urllib.request.Request(BASE + path, data=data, method="POST" if data is not None else "GET", headers={**H, "Content-Type": ctype, **(extra or {})})
    with urllib.request.urlopen(r) as f: return f.read()
pose = {k: np.array(v) for k, v in json.load(open("nus/poses.json")).items()}
graph = json.load(open("nus/merged.json"))
pts = np.vstack([apply(pose[s], load(s)) for s in pose if s != "nus-computing"]).astype("<f4")
version = json.loads(call("/rest/v1/rpc/ab_next_version", {"slug": slug}))
path = f"{slug}/v{version}/points.f32.gz"
call(f"/storage/v1/object/aiseebin-maps/{path}", raw=gzip.compress(pts.tobytes()), ctype="application/gzip", extra={"x-upsert": "true"})
call("/rest/v1/ab_map_versions", {"map_slug": slug, "version": version, "source": "web",
     "note": "All 14 Immersal scans from your layout in the aligner, adjusted so places with the same name meet; Immersal multi-map, no world map",
     "graph": graph, "worldmap_path": None, "pointcloud_path": path, "point_count": int(len(pts))}, extra={"Prefer": "return=minimal"})
print("published", slug, "v", version, len(pts), "points")
