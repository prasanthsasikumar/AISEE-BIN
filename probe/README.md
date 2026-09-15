# Immersal vs ARKit — measurement harness

**Throwaway.** This directory and `AISEEBIN/Probe/` exist to answer one question
and then be deleted:

> In a real greenhouse, does Immersal's VPS hold an accurate absolute fix where
> ARKit's saved `ARWorldMap` drifts — and how much floor area does one free-tier
> map (100 images) actually cover?

Nothing in the shipping app depends on any of it, but it **does ship**: as of
build 4 the harness is included in release builds so TestFlight testers can run
a measurement walk. The ruler button sits at the top right of the Navigate
screen and is hidden from VoiceOver, because stamping places means reading names
off the screen, which makes it a sighted operator's tool.

A walk uploads camera images to Immersal's cloud service, and nothing is
uploaded unless someone starts a walk. The configuration screen says so, and it
belongs in the TestFlight "What to Test" notes too.

## Why it is built this way

**Server-side localization over REST**, not the native plugin. `/localizeb64`
needs no xcframework, no build settings and no vendored binary, which is what
keeps the harness deletable. ARKit already provides both inputs it wants —
`frame.capturedImage` and `frame.camera.intrinsics`.

**One walk, both systems.** Immersal is measured on the same frames of the same
`ARSession` that ARKit is tracking with, so no part of the comparison depends on
walking the route twice under different light.

**Ground truth is the stamp button.** There is no survey equipment, so the
operator standing on a known place and tapping its name *is* the reference. Both
systems are then scored identically: fit one rigid 2D transform from a system's
estimates onto the surveyed place coordinates and report the residuals. Neither
frame is privileged, and a rigid fit removes only the arbitrary choice of origin
and north — it cannot absorb real error.

**Everything Immersal returns is logged raw.** The REST rotation convention is
undocumented, so `imm_r00…r22` are stored exactly as received and interpreted in
post-processing, where all four candidate readings can be tried against the data.
Position never depends on this; only headings do.

**There is no confidence score.** `/localizeb64` does not return one. The stand-in
is `odom_disagreement_m`: how far Immersal's reported motion between consecutive
fixes differs from ARKit's odometry over the same interval. It is deliberately
convention-free — a distance is invariant to the unknown transform between the
two frames — so it is trustworthy even before the rotation reading is settled.
A large disagreement while barely moving is a *confidently wrong fix*, which for
a blind visitor is worse than no fix at all.

## Before the walk

1. Free account at the Immersal Developer Portal.
2. **Immersal Mapper** app: map the glasshouse interior (≤100 images on the free
   tier), then a **second, overlapping** map covering the doorway and the first
   ~15 m of outdoor path. Note the numeric map ids once both finish constructing.
3. Install the app's own map on the device as usual, so ARKit has an
   `ARWorldMap` to relocalize against. Without one, the walk measures Immersal
   alone — the probe screen says so.
4. Ruler button, top right of Navigate → paste the token and the map ids. They
   are stored in `UserDefaults` on that device only and are never written to
   this repo, so each tester enters their own.

## The walk

Tap **Protocol** in the harness for the same list on the phone.

1. **Cold start at the entrance.** Stand still; both systems are racing for a
   first fix. Do not walk until one lands.
2. **Walk the fixed loop.** Stop at each place, stand on the spot, tap its name.
3. **Cover the lens for five seconds, twice**, with the marker buttons either side.
4. **Out through the doorway** — marker, ~15 m along the path, turn, back in, marker.
5. **Re-stamp the first two interior places.** This is what exposes drift
   accumulated outside.
6. **Finish**, then export the CSV before closing the app.

Repeat the whole walk at a different time of day if there is time; sun angle is
the variable most likely to separate the two systems.

## After the walk

```sh
python3 probe/analyse.py probe-20260913T1030.csv --map greenhouse.map.json
python3 probe/analyse.py probe-20260913T1030.csv --plots figures.png   # needs matplotlib
```

`--map` takes the graph JSON holding the surveyed place coordinates; without it
the script falls back to the bundled sample layout and says so.

Reported: time to first fix, availability, latency, position error at the
stamps, revisit drift, recovery after occlusion, the indoor/outdoor split, fix
plausibility, and which rotation convention the data supports.

**Read the plausibility section before the medians.** A median hides blunders,
and blunders are the finding that decides whether this is safe to ship.

Immersal accuracy is reported twice — trusted fixes only, and including flagged
ones. The gap between those two lines is the cost of a blunder.

## Verifying the analysis

The maths was checked against a walk with known ground truth before any real
walk existed: 0.15 m of injected noise reads back as a 0.17 m median residual,
injected ARKit drift separates the raw and best-fit error, a planted 9 m jump is
flagged and excluded from the alignment, and the planted rotation convention is
recovered. `AISEEBINTests/ProbeMathTests.swift` covers the on-device half —
rotation indexing, the axis flip staying a rotation rather than a reflection,
intrinsics scaling, frame-invariance of the disagreement metric, and the CSV
schema.

## Deleting it afterwards

```sh
rm -rf probe AISEEBIN/Probe AISEEBINTests/ProbeMathTests.swift
```

Then remove the two call sites: `onProbeFrame` in
`AISEEBIN/Managers/ARNavigationManager.swift`, and `showingProbe` with its
overlay and cover in `AISEEBIN/Views/ContentView.swift`. Run `xcodegen generate`
afterwards.
