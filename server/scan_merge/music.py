"""Original 30 s, 128 BPM electronic track (synthesised; no samples)."""
import numpy as np, wave, sys
SR = 44100; BPM = 128; BEAT = 60 / BPM; BAR = 4 * BEAT; DUR = 30.0
N = int(SR * DUR); t = np.arange(N) / SR
out = np.zeros((N, 2))
rng = np.random.default_rng(7)
def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR); j = min(N, i + len(sig))
    if i >= N: return
    s = sig[: j - i] * gain
    out[i:j, 0] += s * (1 - max(pan, 0)); out[i:j, 1] += s * (1 + min(pan, 0))
def env(n, a=0.002, d=0.2):
    x = np.arange(n) / SR; return np.minimum(1, x / a) * np.exp(-x / d)
def kick():
    n = int(0.45 * SR); x = np.arange(n) / SR
    f = 45 + 110 * np.exp(-x * 30); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-x * 7) * 1.0 + np.sin(2 * np.pi * 1800 * x) * np.exp(-x * 400) * 0.25
def clap():
    n = int(0.25 * SR); x = np.arange(n) / SR; nz = rng.standard_normal(n)
    e = np.exp(-x * 18) + 0.6 * np.exp(-((x - 0.01) % 0.012) * 300) * (x < 0.035)
    from scipy.signal import butter, lfilter
    b, a = butter(2, [900 / (SR / 2), 5000 / (SR / 2)], "band"); return lfilter(b, a, nz) * e * 0.9
def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR); x = np.arange(n) / SR
    from scipy.signal import butter, lfilter
    b, a = butter(2, 7000 / (SR / 2), "high"); return lfilter(b, a, rng.standard_normal(n)) * np.exp(-x * (14 if open_ else 70)) * 0.35
def saw(f, n, det=0.0):
    x = np.arange(n) / SR; s = 0
    for k in (-det, 0, det): s = s + 2 * ((x * f * (1 + k)) % 1) - 1
    return s / 3
def lowpass(sig, fc):
    from scipy.signal import butter, lfilter
    b, a = butter(2, min(fc, SR / 2 - 100) / (SR / 2)); return lfilter(b, a, sig)
def note(m): return 440 * 2 ** ((m - 69) / 12)
# progression (A minor): Am F C G, one bar each
prog = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [55, 60, 64]), (55, [55, 59, 62])]
bars = int(DUR / BAR)
for b in range(bars + 1):
    t0 = b * BAR; root, chord = prog[b % 4]
    intro = b < 2; outro = b >= bars - 1
    for k in range(4):                      # four-on-the-floor (intro: half-time kicks)
        if intro and k % 2: continue
        add(kick(), t0 + k * BEAT, gain=0.9)
    if not intro:
        for k in (1, 3): add(clap(), t0 + k * BEAT, gain=0.7)
    for k in range(8):                      # hats on the off-beats, 16ths in the drop
        add(hat(open_=(k % 2 == 1)), t0 + k * BEAT / 2 + BEAT / 4 * (k % 2 == 1) * 0, pan=0.3, gain=0.32 if k % 2 else 0.18)
    if not intro:
        for k in range(16): add(hat(), t0 + k * BEAT / 4, pan=-0.3, gain=0.10)
    # bass: off-beat 8ths, sidechain feel
    for k in range(8):
        if k % 2 == 0 and not intro: continue
        n = int(BEAT / 2 * SR * 0.9); s = lowpass(saw(note(root - 12), n, 0.004), 900 if not intro else 300) * env(n, 0.003, 0.18)
        add(s, t0 + k * BEAT / 2, gain=0.55)
    # pluck arp, 16ths
    cut = 1200 + 3800 * min(1, b / 6)
    for k in range(16):
        m = chord[k % 3] + (12 if k % 8 >= 4 else 0) + 12
        n = int(BEAT / 4 * SR * 1.6); s = lowpass(saw(note(m), n, 0.006), cut) * env(n, 0.002, 0.09)
        add(s, t0 + k * BEAT / 4, pan=(0.4 if k % 2 else -0.4), gain=0.22 if not intro else 0.14)
    # pad
    if not intro:
        n = int(BAR * SR); pad = sum(lowpass(saw(note(m), n, 0.01), 1500) for m in chord) / 3
        x = np.arange(n) / SR; pad *= np.minimum(1, x / 0.3) * np.minimum(1, (BAR - x) / 0.3)
        add(pad, t0, gain=0.18)
# riser into the drop (bar 1 -> 2) and a crash at the drop
n = int(BAR * SR); x = np.arange(n) / SR
riser = lowpass(rng.standard_normal(n), 8000) * (x / BAR) ** 2 * 0.35
add(riser, BAR * 1)
crash = lowpass(rng.standard_normal(int(1.5 * SR)), 9000) * np.exp(-np.arange(int(1.5 * SR)) / SR * 2.5) * 0.35
add(crash, BAR * 2); add(crash, BAR * 10)
# sidechain pump on everything but the kick: duck after each beat
pump = 1 - 0.45 * np.exp(-((t % BEAT) / 0.09))
out *= pump[:, None]
# re-add kicks unducked for punch
for b in range(bars + 1):
    for k in range(4):
        if b < 2 and k % 2: continue
        add(kick(), b * BAR + k * BEAT, gain=0.35)
# fade the last 1.2 s, final hit
fade = np.ones(N); m = int((DUR - 1.2) * SR); fade[m:] = np.linspace(1, 0, N - m) ** 1.5; out *= fade[:, None]
out = np.stack([lowpass(out[:, 0], 11000), lowpass(out[:, 1], 11000)], 1)
out /= np.max(np.abs(out)) * 1.05
out = np.tanh(out * 1.6) / np.tanh(1.6)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out * 32000).astype("<i2").tobytes())
print("bars", bars, "beat", BEAT)
