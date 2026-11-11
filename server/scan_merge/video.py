"""Showcase video of the merged NUS COM map, rendered from the real point cloud."""
import json, base64, heapq, math, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
OUT = sys.argv[1]; PREVIEW = len(sys.argv) > 2
Wd, Ht, FPS = 1920, 1080, 30
d = json.load(open("nus/viewdata.json"))
P = (np.frombuffer(base64.b64decode(d["pts"]), dtype="<i2").reshape(-1, 3) / 100).astype(np.float32)
S = np.frombuffer(base64.b64decode(d["scan"]), dtype=np.uint8)
scans = d["scans"]; nodes = {n["id"]: n for n in d["nodes"]}
# heights for nodes without one
adj = {}
for a, b in d["edges"]: adj.setdefault(a, []).append(b); adj.setdefault(b, []).append(a)
for _ in range(20):
    for n in d["nodes"]:
        if n["y"] is None:
            ys = [nodes[m]["y"] for m in adj.get(n["id"], []) if nodes[m]["y"] is not None]
            if ys: n["y"] = sum(ys) / len(ys)
for n in d["nodes"]:
    if n["y"] is None: n["y"] = 0
# rotate whole map so its long axis is horizontal on screen
c = P[:, [0, 2]] - P[:, [0, 2]].mean(0); ev = np.linalg.eigh(np.cov(c.T))[1][:, -1]
ROT = -math.atan2(ev[1], ev[0])
def rz(x, z):
    cr, sr = math.cos(ROT), math.sin(ROT); return x * cr - z * sr, x * sr + z * cr
X, Z = rz(P[:, 0], P[:, 2]); P = np.stack([X, P[:, 1], Z], 1).astype(np.float32)
for n in d["nodes"]: n["x"], n["z"] = rz(n["x"], n["z"])
PAL = np.array([[230,25,75],[60,180,75],[67,99,216],[245,130,48],[145,30,180],[66,212,244],[240,50,230],[191,239,69],[250,190,212],[70,153,144],[220,190,255],[154,99,36],[255,225,25],[255,138,101]], np.float32) / 255
colScan = PAL[S % len(PAL)]
yabs = P[:, 1] + d["center"][1]
t = np.clip((yabs - 2.3) / 1.0, 0, 1)
def hsl(h, s, l):
    import colorsys; return colorsys.hls_to_rgb(h, l, s)
lowc, highc = np.array([0.20, 0.55, 1.0]), np.array([1.0, 0.55, 0.10])
colH = (lowc[None] * (1 - t[:, None]) + highc[None] * t[:, None]).astype(np.float32)
# tour route through the stops, shortest paths
def dist(a, b): A, B = nodes[a], nodes[b]; return math.dist((A["x"], A["y"], A["z"]), (B["x"], B["y"], B["z"]))
def sp(a, b):
    D = {a: 0}; prev = {}; q = [(0, a)]
    while q:
        dd, x = heapq.heappop(q)
        if x == b: break
        for y in adj.get(x, []):
            nd = dd + dist(x, y)
            if nd < D.get(y, 1e9): D[y] = nd; prev[y] = x; heapq.heappush(q, (nd, y))
    path = [b]
    while path[-1] != a: path.append(prev[path[-1]])
    return path[::-1]
stops = ["nus15/entrance", "nus15/water", "nus2/mph-2", "nus2/makan", "nus3/order-kiosk", "nus3/terrace", "nus5/security", "nus7/com-1", "nus8/technical-serviced", "nus8/robotics"]
route = [stops[0]]
for a, b in zip(stops, stops[1:]): route += sp(a, b)[1:]
RP = np.array([[nodes[i]["x"], nodes[i]["y"] - 1.0, nodes[i]["z"]] for i in route])
seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(RP, axis=0), axis=1))]; L = seg[-1]
def along(s):
    s = min(max(s, 0), L); i = min(np.searchsorted(seg, s, side="right") - 1, len(RP) - 2)
    f = (s - seg[i]) / max(seg[i + 1] - seg[i], 1e-6); return RP[i] * (1 - f) + RP[i + 1] * f, i
places = [n for n in d["nodes"] if n["cat"] in ("destination", "exhibit")]

FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
def font(size, bold=True): return ImageFont.truetype(FONT, size, index=1 if bold else 0)
F_T, F_S, F_L, F_C = font(84), font(36, False), font(24), font(30)
BG = np.array([11, 19, 34], np.float32) / 255
ORANGE = (239, 124, 0)

def camera(target, yaw, pitch, distm, fov=45):
    cy, sy, cp, sp_ = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    eye = np.array(target) + distm * np.array([sy * cp, sp_, cy * cp])
    f = np.array(target) - eye; f /= np.linalg.norm(f)
    r = np.array([-cy, 0.0, sy]); u = np.cross(r, f); u /= np.linalg.norm(u)
    k = (Ht / 2) / math.tan(math.radians(fov) / 2)
    def proj(p):
        q = np.asarray(p, np.float32) - eye
        x, y, z = q @ r, q @ u, q @ f
        z = np.maximum(z, 0.1)
        return Wd / 2 + k * x / z, Ht / 2 + 70 - k * y / z, z
    return proj

def splat(proj, pts, cols, alpha, size=2):
    sx, sy, z = proj(pts)
    ok = (sx >= 0) & (sx < Wd - size) & (sy >= 0) & (sy < Ht - size) & (alpha > 0.01)
    sx, sy, cols, al = sx[ok].astype(int), sy[ok].astype(int), cols[ok], alpha[ok]
    acc = np.zeros((Ht, Wd, 3), np.float32); cnt = np.zeros((Ht, Wd), np.float32)
    for dx in range(size):
        for dy in range(size):
            np.add.at(acc, (sy + dy, sx + dx), cols * al[:, None]); np.add.at(cnt, (sy + dy, sx + dx), al)
    a = np.clip(cnt * 0.7, 0, 1)[..., None]
    col = acc / np.maximum(cnt, 1e-6)[..., None]
    img = BG * (1 - a) + col * a
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))

def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def lerp(a, b, x): return a + (b - a) * x

T_INTRO, T_SCANS, T_TILT, T_ROUTE, T_END = 3.0, 12.0, 9.0, 14.0, 4.0
TOTAL = T_INTRO + T_SCANS + T_TILT + T_ROUTE + T_END
center = P.mean(0); ext = np.ptp(P[:, [0, 2]], 0)
top_dist = max(ext[0] / 1.6, ext[1] / 0.9) * 1.45
scan_order = sorted(range(len(scans)), key=lambda i: int(scans[i][3:]) if scans[i][3:].isdigit() else 99)
scan_order = [scans.index("nus15")] + [i for i in scan_order if scans[i] != "nus15"]
appear = np.zeros(len(scans)); 
for k, i in enumerate(scan_order): appear[i] = T_INTRO + k * (T_SCANS - 1.5) / len(scans)

def text(dr, xy, s, f, fill=(255, 255, 255), anchor="la", shadow=True):
    if shadow: dr.text((xy[0] + 2, xy[1] + 2), s, font=f, fill=(0, 0, 0), anchor=anchor)
    dr.text(xy, s, font=f, fill=fill, anchor=anchor)

def frame(tm):
    # camera path
    if tm < T_INTRO + T_SCANS:
        yaw, pitch, dist_ = 0.0, math.radians(89), top_dist * lerp(1.15, 1.0, ease(tm / 6))
    elif tm < T_INTRO + T_SCANS + T_TILT:
        x = ease((tm - T_INTRO - T_SCANS) / T_TILT)
        yaw, pitch, dist_ = lerp(0, math.radians(-50), x), lerp(math.radians(89), math.radians(32), x), top_dist * lerp(1.0, 0.95, x)
    else:
        x = (tm - T_INTRO - T_SCANS - T_TILT) / (T_ROUTE + T_END)
        yaw, pitch, dist_ = math.radians(-50) + x * math.radians(70), math.radians(lerp(32, 40, x)), top_dist * 0.95
    proj = camera(center, yaw, pitch, dist_)
    # colours: scan -> height during the tilt
    mix = ease((tm - T_INTRO - T_SCANS - 2) / 4)
    cols = colScan * (1 - mix) + colH * mix
    alpha = np.clip((tm - appear[S]) / 0.8, 0, 1) if tm < T_INTRO + T_SCANS + 1 else np.ones(len(S))
    alpha = alpha * (0.35 + 0.65 * ease(tm / 1.5))
    scan_alpha = np.clip((tm - appear) / 0.8, 0, 1)
    img = splat(proj, P, cols, alpha.astype(np.float32))
    img = Image.blend(img, img.filter(ImageFilter.GaussianBlur(3)), 0.25)
    dr = ImageDraw.Draw(img, "RGBA")
    # route graph (faint) once scans are in
    gal = ease((tm - T_INTRO) / 1.5)
    if gal > 0:
        for a, b in d["edges"]:
            A, B = nodes[a], nodes[b]
            ea = min(scan_alpha[scans.index(a.split("/")[0])], scan_alpha[scans.index(b.split("/")[0])])
            if ea <= 0.01: continue
            (x1, y1, _), (x2, y2, _) = [proj(np.array([[N["x"], N["y"] - 1.0, N["z"]]])) for N in (A, B)]
            dr.line([(float(x1[0]), float(y1[0])), (float(x2[0]), float(y2[0]))], fill=(255, 255, 255, int(110 * gal * ea)), width=2)
    phase_route = tm - (T_INTRO + T_SCANS + T_TILT)
    if phase_route > 0:
        s = L * ease(phase_route / (T_ROUTE - 1.0))
        n = max(2, int(s / 0.5)); pts = np.array([along(v)[0] for v in np.linspace(0, s, n)])
        sx, sy, _ = proj(pts)
        dr.line(list(zip(sx.tolist(), sy.tolist())), fill=(255, 255, 255, 255), width=6)
        (px, py, _), = [proj(np.array([along(s)[0] + np.array([0, 0.6, 0])]))]
        r = 13 + 3 * math.sin(tm * 8)
        dr.ellipse([px[0] - r, py[0] - r, px[0] + r, py[0] + r], fill=ORANGE + (255,), outline=(255, 255, 255, 255), width=5)
        text(dr, (px[0] + 20, py[0] - 30), "SoCat", F_L, fill=ORANGE)
    # place labels
    lal = ease((tm - T_INTRO - T_SCANS + 1) / 2) if tm < T_INTRO + T_SCANS + T_TILT else 1
    for n in places:
        x, y, z = proj(np.array([[n["x"], n["y"] - 1.0, n["z"]]]))
        x, y = float(x[0]), float(y[0])
        if not (0 < x < Wd and 0 < y < Ht) or lal <= 0: continue
        dr.ellipse([x - 7, y - 7, x + 7, y + 7], fill=ORANGE + (int(255 * lal),), outline=(0, 0, 0, int(255 * lal)), width=2)
        if lal > 0.3: text(dr, (x + 12, y - 12), n["name"], F_L, fill=(255, 255, 255))
    # captions
    if tm < T_INTRO + 0.6:
        a = 1 - ease((tm - T_INTRO + 0.4) / 1.0)
        dr.rectangle([0, 0, Wd, Ht], fill=(11, 19, 34, int(170 * a)))
        text(dr, (Wd / 2, Ht / 2 - 40), "NUS Open House Guide", F_T, anchor="mm")
        text(dr, (Wd / 2, Ht / 2 + 50), "A walkable map of the School of Computing, scanned on a phone", F_S, fill=(200, 210, 230), anchor="mm")
    elif tm < T_INTRO + T_SCANS:
        k = int(np.sum(appear <= tm)); text(dr, (80, 70), f"Scan {k} of {len(scans)}", F_C, fill=ORANGE)
        text(dr, (80, 115), "Fourteen short phone scans, joined into one building map", F_S)
    elif tm < T_INTRO + T_SCANS + T_TILT:
        text(dr, (80, 70), "Two floors", F_C, fill=ORANGE)
        text(dr, (80, 115), "Blue: entrance level   ·   Orange: upper level, 4.6 m up", F_S)
    elif tm < TOTAL - T_END:
        text(dr, (80, 70), "Follow SoCat", F_C, fill=ORANGE)
        text(dr, (80, 115), "Entrance  ·  Water  ·  MPH  ·  Makan  ·  Terrace  ·  COM1  ·  Robotics", F_S)
    else:
        a = ease((tm - (TOTAL - T_END)) / 1.0)
        dr.rectangle([0, 0, Wd, Ht], fill=(11, 19, 34, int(200 * a)))
        if a > 0.2:
            text(dr, (Wd / 2, Ht / 2 - 70), "NUS Open House Guide", F_T, anchor="mm")
            text(dr, (Wd / 2, Ht / 2 + 20), f"{len(scans)} scans  ·  {len(d['nodes'])} route points  ·  {len(places)} places  ·  2 floors", F_S, fill=(200, 210, 230), anchor="mm")
            text(dr, (Wd / 2, Ht / 2 + 80), "Positioning with Immersal, on the phone  ·  NUS School of Computing, 11 Nov 2026", F_S, fill=(200, 210, 230), anchor="mm")
    return img

if PREVIEW:
    for tm in [1, 8, 14, 20, 26, 33, 41]:
        frame(tm).resize((960, 540)).save(f"video/preview_{tm:02d}.png")
    print("previews written; total", TOTAL, "s; route", round(L), "m"); sys.exit()
ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{Wd}x{Ht}", "-r", str(FPS), "-i", "-",
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
N = int(TOTAL * FPS)
for i in range(N):
    ff.stdin.write(frame(i / FPS).convert("RGB").tobytes())
    if i % 150 == 0: print(f"{i}/{N}", flush=True)
ff.stdin.close(); ff.wait(); print("done", OUT)
