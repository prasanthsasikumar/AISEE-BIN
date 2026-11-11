"""30 s high-energy showcase, cut to the 128 BPM track."""
import json, base64, heapq, math, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
OUT = sys.argv[1]; PREVIEW = sys.argv[2:] 
Wd, Ht, FPS = 1920, 1080, 30
BEAT = 60 / 128; BAR = 4 * BEAT; DUR = 30.0
d = json.load(open("nus/viewdata.json")); tr = json.load(open("video/trails.json"))
P = (np.frombuffer(base64.b64decode(d["pts"]), dtype="<i2").reshape(-1, 3) / 100).astype(np.float32)
S = np.frombuffer(base64.b64decode(d["scan"]), dtype=np.uint8); scans = d["scans"]
nodes = {n["id"]: n for n in d["nodes"]}; adj = {}
for a, b in d["edges"]: adj.setdefault(a, []).append(b); adj.setdefault(b, []).append(a)
for _ in range(30):
    for n in d["nodes"]:
        if n["y"] is None:
            ys = [nodes[m]["y"] for m in adj.get(n["id"], []) if nodes[m]["y"] is not None]
            if ys: n["y"] = sum(ys) / len(ys)
for n in d["nodes"]:
    if n["y"] is None: n["y"] = 0
c = P[:, [0, 2]] - P[:, [0, 2]].mean(0); ev = np.linalg.eigh(np.cov(c.T))[1][:, -1]; ROT = -math.atan2(ev[1], ev[0])
def rz(x, z): cr, sr = math.cos(ROT), math.sin(ROT); return x * cr - z * sr, x * sr + z * cr
X, Z = rz(P[:, 0], P[:, 2]); P = np.stack([X, P[:, 1], Z], 1).astype(np.float32)
for n in d["nodes"]: n["x"], n["z"] = rz(n["x"], n["z"])
TR = {k: np.array([rz(x, z) for x, z in v]) for k, v in tr.items()}
PAL = np.array([[255,77,109],[72,219,120],[80,140,255],[255,150,40],[190,90,255],[60,220,255],[255,80,220],[200,255,80],[255,190,212],[40,200,180],[220,190,255],[230,160,60],[255,230,40],[255,138,101]], np.float32) / 255
colScan = PAL[S % len(PAL)]
yabs = P[:, 1] + d["center"][1]; tH = np.clip((yabs - 2.3), 0, 1)
colH = (np.array([0.22, 0.55, 1.0])[None] * (1 - tH[:, None]) + np.array([1.0, 0.5, 0.05])[None] * tH[:, None]).astype(np.float32)
# route
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
RP = np.array([[nodes[i]["x"], nodes[i]["y"] - 1.1, nodes[i]["z"]] for i in route])
seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(RP, axis=0), axis=1))]; L = seg[-1]
def along(s):
    s = min(max(s, 0), L - 1e-3); i = min(np.searchsorted(seg, s, side="right") - 1, len(RP) - 2)
    f = (s - seg[i]) / max(seg[i + 1] - seg[i], 1e-6); return RP[i] * (1 - f) + RP[i + 1] * f
stop_s = {}
for sid in stops: stop_s[sid] = seg[route.index(sid)]
places = [n for n in d["nodes"] if n["cat"] in ("destination", "exhibit")]
F = lambda size: ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Black.ttf", size)
FH = lambda size, b=True: ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=1 if b else 0)
BG = np.array([7, 12, 24], np.float32) / 255; ORANGE = (255, 138, 0); BLUE = (40, 140, 255)
shots = [Image.open(f"video/shot_{k}.png").convert("RGB") for k in "acdbe"]

def camera(target, yaw, pitch, distm, fov=50, oy=40):
    cy, sy, cp, spp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    eye = np.array(target, float) + distm * np.array([sy * cp, spp, cy * cp])
    f = np.array(target, float) - eye; f /= np.linalg.norm(f)
    r = np.array([-cy, 0.0, sy]); u = np.cross(r, f); u /= np.linalg.norm(u)
    k = (Ht / 2) / math.tan(math.radians(fov) / 2)
    def proj(p):
        q = np.asarray(p, np.float32) - eye
        x, y, z = q @ r, q @ u, q @ f; z = np.maximum(z, 0.3)
        return Wd / 2 + k * x / z, Ht / 2 + oy - k * y / z, z
    return proj
def splat(proj, pts, cols, alpha, size=2, gain=0.8):
    sx, sy, z = proj(pts)
    ok = (sx >= 0) & (sx < Wd - size) & (sy >= 0) & (sy < Ht - size) & (alpha > 0.01) & (z > 0.5)
    sx, sy, cols, al = sx[ok].astype(int), sy[ok].astype(int), cols[ok], alpha[ok]
    acc = np.zeros((Ht, Wd, 3), np.float32); cnt = np.zeros((Ht, Wd), np.float32)
    for dx in range(size):
        for dy in range(size):
            np.add.at(acc, (sy + dy, sx + dx), cols * al[:, None]); np.add.at(cnt, (sy + dy, sx + dx), al)
    a = np.clip(cnt * gain, 0, 1)[..., None]; col = acc / np.maximum(cnt, 1e-6)[..., None]
    return BG * (1 - a) + col * a
def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
def back(x):  # overshoot
    x = min(max(x, 0), 1); c1 = 1.70158; c3 = c1 + 1; return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2
def lerp(a, b, x): return a + (b - a) * x
def beatpulse(t): ph = (t % BEAT) / BEAT; return math.exp(-ph * 6)
def to_img(arr): return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
def slam(dr, img, text, f, cx, cy, t, fill=(255, 255, 255), shadow=True):
    s = back(t / 0.28)
    if s <= 0.02: return
    fs = max(8, int(f.size * s)); ff = F(fs) if f.path.endswith("Black.ttf") else FH(fs)
    if shadow: dr.text((cx + 4, cy + 5), text, font=ff, fill=(0, 0, 0), anchor="mm")
    dr.text((cx, cy), text, font=ff, fill=fill, anchor="mm")
center = P.mean(0); ext = np.ptp(P[:, [0, 2]], 0); TOP = max(ext[0] / 1.75, ext[1] / 0.98) * 1.25
order = [scans.index("nus15")] + [i for i in sorted(range(len(scans)), key=lambda i: int(scans[i][3:])) if scans[i] != "nus15"]
B = lambda n: n * BAR

def frame(t):
    pulse = beatpulse(t) if t >= B(2) else beatpulse(t) * 0.5
    txt = []  # deferred drawing
    if t < B(2):                                   # 1. title over a slowly turning cloud
        x = t / B(2)
        proj = camera(center, -0.6 + x * 0.6, math.radians(lerp(25, 60, x)), TOP * lerp(1.6, 1.15, x))
        arr = splat(proj, P, colScan * 0.55, np.full(len(P), 0.35 + 0.4 * x, np.float32))
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        slam(dr, img, "NUS OPEN HOUSE", F(130), Wd / 2, Ht / 2 - 70, t)
        slam(dr, img, "GUIDE", F(130), Wd / 2, Ht / 2 + 70, t - 2 * BEAT, fill=ORANGE)
        slam(dr, img, "follow SoCat through the School of Computing", FH(40, False), Wd / 2, Ht / 2 + 170, t - 4 * BEAT, fill=(210, 220, 240))
    elif t < B(5):                                 # 2. scans slam in
        lt = t - B(2); n_in = min(len(scans), int(lt / (B(3) / len(scans))) + 1)
        appear = np.zeros(len(scans))
        for k, i in enumerate(order): appear[i] = k * B(3) / len(scans)
        al = np.clip((lt - appear[S]) / 0.12, 0, 1).astype(np.float32)
        proj = camera(center, 0.0, math.radians(88), TOP * (1.0 - 0.03 * pulse))
        arr = splat(proj, P, colScan, al, gain=1.0)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        text_scan = min(n_in, len(scans))
        dr.text((90, 70), f"{text_scan:02d}", font=F(150), fill=ORANGE)
        dr.text((90 + 200, 110), "PHONE SCANS", font=F(64), fill=(255, 255, 255))
        dr.text((90 + 205, 190), "one morning · one iPhone", font=FH(34, False), fill=(200, 210, 230))
    elif t < B(7):                                 # 3. one walk lines them up
        lt = t - B(5)
        proj = camera(center, 0.0, math.radians(88), TOP * 0.98)
        arr = splat(proj, P, colScan * 0.35 + 0.15, np.full(len(P), 0.6, np.float32), gain=0.9)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        for key, col, t0 in (("old", (255, 70, 70), 0.0), ("new", BLUE, B(1) * 0.55)):
            p = TR[key]; k = int(len(p) * ease((lt - t0) / (B(1) * 1.2)))
            if k > 2:
                q = np.stack([p[:k, 0], np.full(k, -1.0), p[:k, 1]], 1)
                sx, sy, _ = proj(q); dr.line(list(zip(sx.tolist(), sy.tolist())), fill=col + (255,), width=7 if key == "new" else 5)
        slam(dr, img, "ONE WALK.", F(96), Wd / 2, 120, lt)
        slam(dr, img, "EVERY SCAN LINED UP", F(72), Wd / 2, 220, lt - 2 * BEAT, fill=ORANGE)
        dr.text((80, Ht - 90), "red: before   ", font=FH(34), fill=(255, 90, 90)); dr.text((300, Ht - 90), "blue: calibrated  ·  0.1–0.4 m between scans", font=FH(34), fill=(120, 180, 255))
    elif t < B(9):                                 # 4. into 3D, two floors
        x = ease((t - B(7)) / B(2))
        proj = camera(center, lerp(0.0, -1.2, x), math.radians(lerp(88, 30, x)), TOP * lerp(0.98, 0.78, x))
        mix = ease((t - B(7)) / 1.2); cols = colScan * (1 - mix) + colH * mix
        arr = splat(proj, P, cols, np.ones(len(P), np.float32), gain=0.9)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        slam(dr, img, "2 FLOORS", F(120), Wd / 2, 110, t - B(7))
        slam(dr, img, "entrance level  +  upper level 4.6 m up", FH(40), Wd / 2, 200, t - B(7) - 2 * BEAT, fill=(230, 235, 245))
    elif t < B(13):                                # 5. chase SoCat along the route
        lt = t - B(9); s = L * ease(lt / (B(4) - 0.2)) if lt < B(4) else L
        s = L * (lt / B(4)) ** 1.1 if True else s
        s = min(s, L - 0.01)
        pos = along(s); ahead = along(min(L - 0.01, s + 18)) - along(max(0, s - 6)); hd = math.atan2(ahead[0], ahead[2])
        proj = camera(pos + np.array([0, 2.0, 0]), hd, math.radians(34), 26, fov=62, oy=90)
        arr = splat(proj, P, colH * 0.85 + colScan * 0.15, np.ones(len(P), np.float32), gain=0.95)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        # route ahead (white) and behind (orange)
        for s0, s1, col, w in ((0, s, ORANGE + (255,), 10), (s, min(L, s + 60), (255, 255, 255, 200), 5)):
            if s1 - s0 < 0.5: continue
            q = np.array([along(v) for v in np.linspace(s0, s1, max(2, int((s1 - s0) / 0.7)))]); sx, sy, z = proj(q)
            pts = [(a, b) for a, b, zz in zip(sx, sy, z) if zz > 4 and -500 < a < Wd + 500 and -500 < b < Ht + 500]
            if len(pts) > 1: dr.line(pts, fill=col, width=w)
        (px,), (py,), _ = proj(np.array([pos + [0, 0.8, 0]]))
        r = 20 + 6 * pulse; dr.ellipse([px - r, py - r, px + r, py + r], fill=ORANGE + (255,), outline=(255, 255, 255, 255), width=6)
        dr.text((px + 30, py - 50), "SoCat", font=F(40), fill=(255, 255, 255))
        # stop labels popping as SoCat passes
        names = {"nus15/water": "WATER", "nus2/mph-2": "MPH", "nus2/makan": "MAKAN", "nus3/order-kiosk": "ORDER KIOSK", "nus3/terrace": "TERRACE", "nus5/security": "SECURITY", "nus7/com-1": "COM1", "nus8/technical-serviced": "TECHNICAL SERVICES", "nus8/robotics": "ROBOTICS"}
        passed = [k for k in names if stop_s[k] <= s]
        if passed:
            k = passed[-1]; since = (s - stop_s[k]) / (L / B(4))
            slam(dr, img, names[k], F(110), Wd / 2, 120, since)
        dr.text((80, Ht - 100), f"{int(s):3d} m", font=F(64), fill=ORANGE)
        dr.text((80 + 230, Ht - 80), "walked with SoCat", font=FH(36), fill=(220, 230, 245))
    elif t < B(15):                                # 6. real phone screens, one per beat
        lt = t - B(13); arr = np.zeros((Ht, Wd, 3), np.float32) + BG
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        for k, shot in enumerate(shots):
            t0 = k * BEAT * 1.2
            if lt < t0: continue
            sc = back((lt - t0) / 0.25); h = int(780 * sc); w = int(h * shot.width / shot.height)
            if h < 20: continue
            im = shot.resize((w, h)); m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, w, h], radius=int(48 * sc), fill=255)
            cx = int(Wd / 2 + (k - 2) * 360); cy = int(Ht / 2 + 40 + (20 if k % 2 else -20))
            sh = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle([20, 20, w + 20, h + 20], radius=48, fill=(0, 0, 0, 160))
            img.paste(sh.filter(ImageFilter.GaussianBlur(14)), (cx - w // 2 - 20, cy - h // 2 - 10), sh.filter(ImageFilter.GaussianBlur(14)))
            img.paste(im, (cx - w // 2, cy - h // 2), m)
        dr = ImageDraw.Draw(img, "RGBA")
        slam(dr, img, "ON THE PHONE", F(80), Wd / 2, 70, lt)
    else:                                          # 7. end card
        lt = t - B(15)
        proj = camera(center, -1.2 + lt * 0.4, math.radians(40), TOP * 0.95)
        arr = splat(proj, P, colH * 0.5, np.full(len(P), 0.5, np.float32))
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        dr.rectangle([0, 0, Wd, Ht], fill=(7, 12, 24, 140))
        slam(dr, img, "NUS OPEN HOUSE GUIDE", F(110), Wd / 2, Ht / 2 - 60, lt)
        slam(dr, img, "14 scans  ·  2 floors  ·  15 stops  ·  1 cat", FH(46), Wd / 2, Ht / 2 + 50, lt - BEAT, fill=ORANGE)
        slam(dr, img, "Hold up your phone and follow SoCat", FH(38, False), Wd / 2, Ht / 2 + 120, lt - 2 * BEAT, fill=(220, 230, 245))
    # beat flash + vignette
    if pulse > 0.05 and t >= B(2) and t < B(15):
        dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(255, 255, 255, int(16 * pulse)))
    for b0 in (B(2), B(5), B(7), B(9), B(13), B(15)):   # white flash on each cut
        if 0 <= t - b0 < 0.12:
            dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(255, 255, 255, int(200 * (1 - (t - b0) / 0.12))))
    if t > DUR - 0.6:
        dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(0, 0, 0, int(255 * (t - DUR + 0.6) / 0.6)))
    return img

if PREVIEW:
    for tm in [float(x) for x in PREVIEW]: frame(tm).resize((960, 540)).save(f"video/p30_{tm:05.2f}.png")
    sys.exit()
ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{Wd}x{Ht}", "-r", str(FPS), "-i", "-",
                       "-i", "video/track.wav", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium",
                       "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
for i in range(int(DUR * FPS)):
    ff.stdin.write(frame(i / FPS).convert("RGB").tobytes())
    if i % 150 == 0: print(i, flush=True)
ff.stdin.close(); ff.wait(); print("done")
