import json, subprocess, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE)
DL = os.path.expanduser('~/Downloads/')
NAV = DL + 'WhatsApp Video 2026-10-01 at 15.41.58.mp4'
LIVE = DL + 'WhatsApp Video 2026-10-01 at 15.29.13.mp4'
CLOUD = DL + 'WhatsApp Video 2026-10-01 at 16.28.57.mp4'
FONT = ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', 42, index=10)
LEAD, TAIL, FPS = 0.2, 0.25, 30

def dur(p):
    return float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', p],
                                capture_output=True, text=True).stdout)

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode: print(r.stderr[-2500:]); raise SystemExit(1)

script = dict(json.load(open('script.json')))

def chunks(text, maxw=1500):
    words, out, cur = text.split(), [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if FONT.getlength(t) > maxw and cur: out.append(cur); cur = w
        else: cur = t
    out.append(cur)
    # pair lines into two-line cards
    return [' \n'.join(out[i:i + 2]).replace(' \n', '\n') for i in range(0, len(out), 2)]

def sub_png(text, path, tag=None):
    img = Image.new('RGBA', (1920, 1080), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    lines = text.split('\n'); lh = 54
    w = max(FONT.getlength(l) for l in lines); h = lh * len(lines)
    x0, y1 = (1920 - w) / 2 - 30, 1040; y0 = y1 - h - 26
    d.rounded_rectangle([x0, y0, x0 + w + 60, y1], 18, fill=(10, 10, 28, 200))
    for i, l in enumerate(lines):
        d.text(((1920 - FONT.getlength(l)) / 2, y0 + 12 + i * lh), l, font=FONT, fill=(255, 255, 255, 255))
    if tag:
        tf = ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', 28, index=1)
        tw = tf.getlength(tag); d.rounded_rectangle([(1920 - tw) / 2 - 16, y0 - 50, (1920 + tw) / 2 + 16, y0 - 10], 14, fill=(108, 76, 245, 235))
        d.text(((1920 - tw) / 2, y0 - 46), tag, font=tf, fill='white')
    img.save(path)

def subs_for(key, start):
    """Subtitle overlays for a scene's narration, timed by characters."""
    n = dur(f'n_{key}.mp3'); cards = chunks(script[key]); total = sum(len(c) for c in cards); t = start; out = []
    for i, c in enumerate(cards):
        d = n * len(c) / total; p = f'sub_{key}_{i}.png'; sub_png(c, p); out.append((p, t, t + d)); t += d
    return out

scenes = []
# (key, background, extra video inputs builder, extra audio)
for key in ['title', 'how', 'ways', 'editor', 'site', 'entrance', 'next']:
    n = dur(f'n_{key}.mp3'); length = LEAD + n + TAIL
    APP = 2.5 if key == 'site' else 0          # the app's own voice at the end of the site scene
    if key == 'next': length += 0.5
    length += APP
    inputs = ['-loop', '1', '-framerate', str(FPS), '-t', f'{length:.3f}', '-i', f'bg/bg_{key}.png']
    fc = []
    # gentle push-in on the background
    fc.append(f"[0:v]scale=2112:1188,zoompan=z='1+0.035*on/({length*FPS:.0f})':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps={FPS}[bg]")
    last = 'bg'; idx = 1
    if key == 'site':
        nav_start = 163.4 - (LEAD + n + TAIL)          # ends on "the Point 1, you have arrived at the Point 1"
        inputs += ['-ss', f'{nav_start:.2f}', '-t', f'{length:.3f}', '-i', NAV,
                   '-ss', '6', '-t', f'{length*2:.3f}', '-i', LIVE]
        fc.append(f"[1:v]fps={FPS},scale=370:800:force_original_aspect_ratio=increase,crop=370:800,format=yuva420p,geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='if(gt(abs(X-185)-157,0)*gt(abs(Y-400)-372,0),if(lte(hypot(abs(X-185)-157,abs(Y-400)-372),28),255,0),255)'[nav]")
        fc.append(f"[2:v]setpts=0.5*PTS,fps={FPS},scale=370:800:force_original_aspect_ratio=increase,crop=370:800,format=yuva420p,geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='if(gt(abs(X-185)-157,0)*gt(abs(Y-400)-372,0),if(lte(hypot(abs(X-185)-157,abs(Y-400)-372),28),255,0),255)'[live]")
        fc.append(f"[{last}][nav]overlay=150:50:shortest=0:eof_action=pass[v1]")
        fc.append(f"[v1][live]overlay=570:50:eof_action=pass[v2]"); last = 'v2'; idx = 3
    if key == 'entrance':
        inputs += ['-t', f'{length:.3f}', '-i', CLOUD]
        fc.append(f"[1:v]fps={FPS},scale=420:700:force_original_aspect_ratio=increase,crop=420:700,format=yuva420p,geq=lum='p(X,Y)':cb='p(X,Y)':cr='p(X,Y)':a='if(gt(abs(X-210)-182,0)*gt(abs(Y-350)-322,0),if(lte(hypot(abs(X-210)-182,abs(Y-350)-322),28),255,0),255)'[cl]")
        fc.append(f"[{last}][cl]overlay=1330:140:eof_action=repeat[v1]"); last = 'v1'; idx = 2
    subs = subs_for(key, LEAD)
    if APP:
        p = 'sub_site_app.png'; sub_png('“…you have arrived at the Point 1.”', p, tag='THE APP SPEAKING')
        subs.append((p, LEAD + n + TAIL, length))
    for p, a, b in subs:
        inputs += ['-loop', '1', '-framerate', str(FPS), '-t', f'{length:.3f}', '-i', p]
        fc.append(f"[{last}][{idx}:v]overlay=0:0:enable='between(t,{a:.2f},{b:.2f})'[s{idx}]"); last = f's{idx}'; idx += 1
    fc.append(f"[{last}]fade=t=in:st=0:d=0.3,fade=t=out:st={length-0.3:.2f}:d=0.3,format=yuv420p[vout]")
    # audio: narration (+ the app's own voice for the site scene)
    inputs += ['-i', f'n_{key}.mp3']; na = idx; idx += 1
    fc.append(f"[{na}:a]adelay={int(LEAD*1000)}|{int(LEAD*1000)},apad,atrim=0:{length:.3f},aformat=sample_rates=44100:channel_layouts=stereo[na]")
    if APP:
        fc.append(f"[1:a]atrim=start={LEAD+n+TAIL:.3f},asetpts=PTS-STARTPTS,volume=2.2,adelay={int((LEAD+n+TAIL)*1000)}|{int((LEAD+n+TAIL)*1000)},apad,atrim=0:{length:.3f},aformat=sample_rates=44100:channel_layouts=stereo[aa]")
        fc.append("[na][aa]amix=inputs=2:normalize=0[aout]")
    else:
        fc.append("[na]anull[aout]")
    out = f'scene_{len(scenes)}_{key}.mp4'
    run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex', ';'.join(fc), '-map', '[vout]', '-map', '[aout]',
         '-t', f'{length:.3f}', '-r', str(FPS), '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p',
         '-c:a', 'aac', '-b:a', '192k', out])
    scenes.append(out); print(key, round(length, 2))

open('list.txt', 'w').write(''.join(f"file '{s}'\n" for s in scenes))
run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', 'list.txt', '-c', 'copy', 'joined.mp4'])
T = dur('joined.mp4')
# music under everything, ducked while anyone speaks
run(['ffmpeg', '-v', 'error', '-y', '-i', 'joined.mp4', '-i', 'music.wav', '-filter_complex',
     f"[1:a]atrim=0:{T:.3f},volume=0.32,afade=t=out:st={T-2.5:.2f}:d=2.5[m];[0:a]asplit[v1][v2];"
     f"[m][v1]sidechaincompress=threshold=0.03:ratio=6:attack=40:release=500[md];[v2][md]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]",
     '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', 'final.mp4'])
print('total', round(T, 2))
