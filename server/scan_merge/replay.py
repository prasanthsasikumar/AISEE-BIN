import json, numpy as np, base64, sys, collections, urllib.request
from PIL import Image, ImageDraw
ev = json.load(open("nus/device/events.json"))
ev.sort(key=lambda e: e["t"])
# placements: v5 (what the phone used) and v6 (corrected)
B="https://djfpemdkeguztyuerxqc.supabase.co";K="sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL";H={"apikey":K,"Authorization":"Bearer "+K}
def graph(v): return json.load(urllib.request.urlopen(urllib.request.Request(B+f"/rest/v1/ab_map_versions?map_slug=eq.nus-com&version=eq.{v}&select=graph",headers=H)))[0]["graph"]
G5, G6 = graph(5), graph(6)
pl5 = {m["id"]: m for m in G5["immersalAlignment"]["maps"]}; pl6 = {m["id"]: m for m in G6["immersalAlignment"]["maps"]}
def fwd(m, x, z): c, s = np.cos(m["yaw"]), np.sin(m["yaw"]); return c*x - s*z + m["tx"], s*x + c*z + m["tz"]
def inv(m, x, z): x, z = x - m["tx"], z - m["tz"]; c, s = np.cos(m["yaw"]), np.sin(m["yaw"]); return c*x + s*z, -s*x + c*z
fixmap = None; maploaded = None; old, new = [], []; fixes = collections.Counter(); att = 0
for e in ev:
    if e["app"] != "nus-open-house": continue
    d = e["data"]
    if e["type"] == "map.loaded": maploaded = (d.get("slug"), d.get("version"))
    if maploaded != ("nus-com", 5): continue
    if e["type"] == "loc.attempt":
        att += 1
        if d.get("ok"): fixes[d.get("map_id")] += 1
        if d.get("accepted"): fixmap = d.get("map_id")
    if e["type"] == "pose" and d.get("localized") and fixmap in pl5:
        x, z = d["x"], d["z"]; old.append((x, z, fixmap))
        ix, iz = inv(pl5[fixmap], x, z); new.append((*fwd(pl6[fixmap], ix, iz), fixmap))
print("attempts", att, "fixes by map", dict(fixes), "localized poses", len(old))
# render over v6 points
d = json.load(open("nus/viewdata.json")); c0 = np.array(d["center"])
P = np.frombuffer(base64.b64decode(d["pts"]), dtype="<i2").reshape(-1, 3) / 100 + c0
allxy = np.array([(a, b) for a, b, _ in old + new] + [(p[0], p[2]) for p in P[::20]])
lo, hi = np.percentile(allxy, 0.5, 0) - 5, np.percentile(allxy, 99.5, 0) + 5
S = 7; W, Hh = int((hi[0]-lo[0])*S), int((hi[1]-lo[1])*S)
im = Image.new("RGB", (W, Hh), "white"); dr = ImageDraw.Draw(im)
X = lambda x, z: ((x-lo[0])*S, (z-lo[1])*S)
for p in P[::2]: dr.point(X(p[0], p[2]), fill=(190, 195, 205))
N = {n["id"]: n for n in G6["pois"]}
for e in G6["edges"]: a, b = N[e["from"]], N[e["to"]]; dr.line([X(a["x"], a["z"]), X(b["x"], b["z"])], fill=(120, 120, 120), width=1)
for n in G6["pois"]:
    if n["category"] in ("destination", "exhibit"): x, y = X(n["x"], n["z"]); dr.ellipse([x-4,y-4,x+4,y+4], fill="black"); dr.text((x+6, y-6), n["name"], fill="black")
for pts, col in ((old, (220, 40, 40)), (new, (0, 120, 255))):
    for x, z, _ in pts: px, py = X(x, z); dr.ellipse([px-2.5, py-2.5, px+2.5, py+2.5], fill=col)
dr.text((10, 10), "red: where the app put you (v5)   blue: same fixes with the corrected placements (v6)", fill="black")
im.save("nus/replay.png"); print(im.size)
