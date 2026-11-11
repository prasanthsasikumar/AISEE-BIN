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
T1, T2, T3, T4, T5, T6 = B(2), B(3.5), B(4.5), B(6), B(13), B(15)   # title | scans | calib | floors | nav | phones | end
NAV_YAW, NAV_PITCH = -0.9, math.radians(42)
NAV_T = np.array([RP[:, 0].mean(), RP[:, 1].mean(), RP[:, 2].mean()])
def fit_dist(yaw, pitch, target, pts, oy=40, margin=(140, 90, 170, 150)):
    lo, hi = 10.0, 400.0
    for _ in range(30):
        m = (lo + hi) / 2; sx, sy, _ = camera(target, yaw, pitch, m, oy=oy)(pts)
        ok = sx.min() > margin[0] and sx.max() < Wd - margin[0] and sy.min() > margin[2] and sy.max() < Ht - margin[3]
        hi, lo = (m, lo) if ok else (hi, m)
    return hi
FRAME_PTS = np.vstack([RP, np.array([[n["x"], n["y"] - 1.1, n["z"]] for n in places])])
NAV_OY = 40
for _ in range(4):   # centre the route between the margins, then fit again
    NAV_DIST = fit_dist(NAV_YAW, NAV_PITCH, NAV_T, FRAME_PTS, oy=NAV_OY)
    sx, sy, _ = camera(NAV_T, NAV_YAW, NAV_PITCH, NAV_DIST, oy=NAV_OY)(FRAME_PTS)
    NAV_OY += ((170 + (Ht - 150)) / 2) - (sy.min() + sy.max()) / 2
    # horizontal: shift the target along the camera's right axis
    off = (Wd / 2) - (sx.min() + sx.max()) / 2
    k = (Ht / 2) / math.tan(math.radians(50) / 2); r = np.array([-math.cos(NAV_YAW), 0.0, math.sin(NAV_YAW)])
    NAV_T = NAV_T - r * off * NAV_DIST / k
NAV_DIST = fit_dist(NAV_YAW, NAV_PITCH, NAV_T, FRAME_PTS, oy=NAV_OY)
print("nav view: dist", round(NAV_DIST, 1), "oy", round(NAV_OY))

def frame(t):
    pulse = math.exp(-((t % BAR) / BAR) * 8)   # gentle, once per bar
    txt = []  # deferred drawing
    if t < T1:                                     # 1. title over a slowly turning cloud
        x = t / B(2)
        proj = camera(NAV_T, -0.6 + x * 0.3, math.radians(lerp(30, 48, x)), NAV_DIST * lerp(1.25, 1.05, x), oy=NAV_OY + 60)
        arr = splat(proj, P, colScan * 0.55, np.full(len(P), 0.35 + 0.4 * x, np.float32))
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        lab_a = int(255 * ease((t - 0.4) / 0.8))
        for n in places:
            (x,), (y,), (z,) = proj(np.array([[n["x"], n["y"] - 1.1, n["z"]]]))
            if not (0 < x < Wd and 0 < y < Ht): continue
            dr.ellipse([x - 5, y - 5, x + 5, y + 5], fill=ORANGE + (lab_a,))
            dr.text((x + 10, y - 12), n["name"], font=FH(26), fill=(240, 244, 252, lab_a))
        slam(dr, img, "NUS OPEN HOUSE GUIDE", F(104), Wd / 2, 110, t)
        slam(dr, img, "follow SoCat through the School of Computing", FH(40, False), Wd / 2, 205, t - 2 * BEAT, fill=ORANGE)
    elif t < T2:                                   # 2. scans slam in
        lt = t - T1; span = (T2 - T1) * 0.85; n_in = min(len(scans), int(lt / (span / len(scans))) + 1)
        appear = np.zeros(len(scans))
        for k, i in enumerate(order): appear[i] = k * span / len(scans)
        al = np.clip((lt - appear[S]) / 0.1, 0, 1).astype(np.float32)
        proj = camera(center, 0.0, math.radians(88), TOP * (1.0 - 0.03 * pulse))
        arr = splat(proj, P, colScan, al, gain=1.0)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        text_scan = min(n_in, len(scans))
        dr.text((90, 70), f"{text_scan:02d}", font=F(150), fill=ORANGE)
        dr.text((90 + 200, 110), "PHONE SCANS", font=F(64), fill=(255, 255, 255))
        dr.text((90 + 205, 190), "one morning · one iPhone", font=FH(34, False), fill=(200, 210, 230))
    elif t < T3:                                   # 3. one walk lines them up
        lt = t - T2
        proj = camera(center, 0.0, math.radians(88), TOP * 0.98)
        arr = splat(proj, P, colScan * 0.35 + 0.15, np.full(len(P), 0.6, np.float32), gain=0.9)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        for key, col, t0 in (("old", (255, 70, 70), 0.0), ("new", BLUE, (T3 - T2) * 0.3)):
            p = TR[key]; k = int(len(p) * ease((lt - t0) / ((T3 - T2) * 0.6)))
            if k > 2:
                q = np.stack([p[:k, 0], np.full(k, -1.0), p[:k, 1]], 1)
                sx, sy, _ = proj(q); dr.line(list(zip(sx.tolist(), sy.tolist())), fill=col + (255,), width=7 if key == "new" else 5)
        slam(dr, img, "ONE WALK.", F(96), Wd / 2, 120, lt)
        slam(dr, img, "EVERY SCAN LINED UP", F(72), Wd / 2, 220, lt - BEAT, fill=ORANGE)
        dr.text((80, Ht - 90), "red: before   ", font=FH(34), fill=(255, 90, 90)); dr.text((300, Ht - 90), "blue: calibrated  ·  0.1–0.4 m between scans", font=FH(34), fill=(120, 180, 255))
    elif t < T4:                                   # 4. into 3D, two floors (ends on the navigation view)
        x = ease((t - T3) / (T4 - T3))
        proj = camera(center * (1 - x) + NAV_T * x, lerp(0.0, NAV_YAW, x), lerp(math.radians(88), NAV_PITCH, x), lerp(TOP * 0.98, NAV_DIST, x), oy=lerp(40, NAV_OY, x))
        mix = ease((t - T3) / 1.0); cols = colScan * (1 - mix) + colH * mix
        arr = splat(proj, P, cols, np.ones(len(P), np.float32), gain=0.9)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        slam(dr, img, "2 FLOORS", F(120), Wd / 2, 110, t - T3)
        slam(dr, img, "entrance level  +  upper level 4.6 m up", FH(40), Wd / 2, 200, t - T3 - BEAT, fill=(230, 235, 245))
    elif t < T5:                                   # 5. SoCat walks the route; the map holds still
        lt = t - T4; s = min(L - 0.01, L * ease(lt / (T5 - T4 - 0.6)))
        proj = camera(NAV_T, NAV_YAW + 0.04 * (lt / (T5 - T4)), NAV_PITCH, NAV_DIST, oy=NAV_OY)   # barely drifts
        arr = splat(proj, P, colH * 0.8 + colScan * 0.2, np.full(len(P), 0.85, np.float32), gain=0.9)
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        q = np.array([along(v) for v in np.linspace(0, L, 400)]); sx, sy, _ = proj(q)
        dr.line(list(zip(sx.tolist(), sy.tolist())), fill=(255, 255, 255, 70), width=3)          # whole route, faint
        if s > 0.5:
            q = np.array([along(v) for v in np.linspace(0, s, max(2, int(s / 0.6)))]); sx, sy, _ = proj(q)
            dr.line(list(zip(sx.tolist(), sy.tolist())), fill=ORANGE + (255,), width=8)          # walked so far
        names = {"nus15/water": "Water", "nus2/mph-2": "MPH", "nus2/makan": "Makan", "nus3/order-kiosk": "Order Kiosk", "nus3/terrace": "Terrace", "nus5/security": "Security", "nus7/com-1": "COM1", "nus8/technical-serviced": "Technical Services", "nus8/robotics": "Robotics"}
        speed = L / (T5 - T4 - 0.6)
        for k, nm in names.items():
            n = nodes[k]; (x,), (y,), _ = proj(np.array([[n["x"], n["y"] - 1.1, n["z"]]]))
            reached = stop_s[k] <= s; since = (s - stop_s[k]) / speed if reached else -1
            r = 9 if not reached else 9 + 10 * max(0, 1 - since / 0.4)
            dr.ellipse([x - r, y - r, x + r, y + r], fill=(ORANGE if reached else (160, 170, 190)) + (255,), outline=(0, 0, 0, 255), width=2)
            sc = back(since / 0.3) if reached else 1
            ff = FH(int(30 * (1 + 0.25 * max(0, 1 - since / 0.6))) if reached else 24)
            dr.text((x + 16, y - 16), nm, font=ff, fill=(255, 255, 255, 255 if reached else 150))
        pos = along(s); (px,), (py,), _ = proj(np.array([pos + [0, 0.8, 0]]))
        r = 18 + 4 * pulse; dr.ellipse([px - r, py - r, px + r, py + r], fill=ORANGE + (255,), outline=(255, 255, 255, 255), width=6)
        dr.text((px + 26, py - 46), "SoCat", font=F(36), fill=(255, 255, 255))
        reached = [k for k in names if stop_s[k] <= s]
        if reached: slam(dr, img, names[reached[-1]].upper(), F(84), Wd / 2, 100, (s - stop_s[reached[-1]]) / speed)
        dr.text((80, Ht - 100), f"{int(s):3d} m", font=F(64), fill=ORANGE)
        dr.text((80 + 230, Ht - 80), "walked with SoCat", font=FH(36), fill=(220, 230, 245))
    elif t < T6:                                   # 6. real phone screens, one per beat
        lt = t - T5; arr = np.zeros((Ht, Wd, 3), np.float32) + BG
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
        lt = t - T6
        proj = camera(NAV_T, NAV_YAW + lt * 0.25, math.radians(40), NAV_DIST, oy=NAV_OY)
        arr = splat(proj, P, colH * 0.5, np.full(len(P), 0.5, np.float32))
        img = to_img(arr); dr = ImageDraw.Draw(img, "RGBA")
        dr.rectangle([0, 0, Wd, Ht], fill=(7, 12, 24, 140))
        slam(dr, img, "NUS OPEN HOUSE GUIDE", F(110), Wd / 2, Ht / 2 - 60, lt)
        slam(dr, img, "14 scans  ·  2 floors  ·  15 stops  ·  1 cat", FH(46), Wd / 2, Ht / 2 + 50, lt - BEAT, fill=ORANGE)
        slam(dr, img, "Hold up your phone and follow SoCat", FH(38, False), Wd / 2, Ht / 2 + 120, lt - 2 * BEAT, fill=(220, 230, 245))
    # beat flash + vignette
    if pulse > 0.05 and T1 <= t < T6:
        dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(255, 255, 255, int(8 * pulse)))
    for b0 in (T1, T2, T3, T5, T6):                     # soft flash on each cut (none into the steady nav view)
        if 0 <= t - b0 < 0.15:
            dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(255, 255, 255, int(90 * (1 - (t - b0) / 0.15))))
    if t > DUR - 0.6:
        dr = ImageDraw.Draw(img, "RGBA"); dr.rectangle([0, 0, Wd, Ht], fill=(0, 0, 0, int(255 * (t - DUR + 0.6) / 0.6)))
    return img

if PREVIEW:
    for tm in [float(x) for x in PREVIEW]: frame(tm).resize((960, 540)).save(f"video/p30_{tm:05.2f}.png")
    sys.exit()
ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{Wd}x{Ht}", "-r", str(FPS), "-i", "-",
                       "-i", "video/track2.wav", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium",
                       "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
for i in range(int(DUR * FPS)):
    ff.stdin.write(frame(i / FPS).convert("RGB").tobytes())
    if i % 150 == 0: print(i, flush=True)
ff.stdin.close(); ff.wait(); print("done")
