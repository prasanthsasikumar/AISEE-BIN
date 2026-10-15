# Lanyard + glasses hybrid positioning

**Date:** 2026-10-16
**Status:** approved in conversation ("yeah A", "yes" to the sectioned design)

## Why

Phone mode has ARKit's smooth 60 Hz tracking but only the chest camera to
localize with; glasses mode has the eye-level camera but no tracker between
fixes except the pedometer and, since today, the gyro. On site (Flower Dome,
2026-10-15) the glasses localized slowly and the phone could not find itself
at the entrance. The idea raised in that discussion: wear the phone on a
lanyard, camera forward, and use **both**: ARKit as the tracker, both cameras
feeding Immersal fixes that anchor the ARKit session to the map.

**Constraint from the user:** this must not affect the other features. The
hybrid is additive; phone mode, glasses (pocket) mode, authoring, field test,
guidance and the beacon keep their code paths and their behaviour.

## Behaviour

- A new positioning choice on the Glasses screen, a picker in place of today's
  on/off toggle: **Phone**, **Glasses, phone in pocket**, **Lanyard + glasses**.
  The first two are exactly today's modes. The glasses choice is remembered
  (`UserDefaults` `positioning.glassesMode`, values `pocket` | `lanyard`,
  default `pocket`), and that remembered choice is what the auto-switch uses
  when the glasses connect. A user who never picks Lanyard sees no change.
- Lanyard needs a map with an Immersal alignment, like pocket mode. Without
  one it refuses with the same wording ("Map not aligned" status; spoken
  "This map has no Immersal map. Using the phone camera.") and stays in phone
  mode. It always starts ARKit **fresh** (no world-map relocalization) and
  anchors by Immersal.
- While it runs: ARKit tracks at 60 Hz; the phone camera localizes about every
  1.2 s with the full pose (today's `PhoneImmersalLocalizer`); the glasses
  stream localizes at the existing glasses cadence (≥0.5 s apart, one in
  flight) as **position only**. The first fix from either camera anchors the
  session; both keep correcting it. Guidance, the live map and the beacon read
  the phone path, so the heading is the chest heading at 60 Hz.
- Spoken start: "Using the phone and the glasses. Please look around slowly."
  Glasses disconnect → "Glasses disconnected. Using the phone camera." and the
  app returns to phone mode, as pocket mode does today. Push-to-talk uses the
  glasses microphone when they are connected, as in pocket mode.
- Stream latency (glasses frame → phone) is a setting, "Glasses stream
  latency", default 0.20 s, in the Glasses screen's lanyard status area.

## The anchor

`ImmersalAnchor.update(graphPose:sessionPose:)` is untouched. It gains:

- `updatePosition(graphPosition: SIMD2<Float>, sessionPose: simd_float4x4) -> Bool`:
  with a fit present, keeps `yaw` and `ty` and refits `tx`/`tz` so the session
  pose's planar position maps onto `graphPosition`, through the same `maxJump`
  gate and the same "`maxRejections` in a row are believed" rule, counting in
  the same `fixes`/`rejected`/`consecutiveRejections`. With no fit, returns
  `false` and changes nothing (the bootstrap handles that case).
- The glasses' head heading is never used for yaw: the glasses are not the
  phone, and the head-to-chest angle is unknown and changing.

`PositionPairBootstrap` (new, pure): collects `(session: SIMD2<Float>,
graph: SIMD2<Float>)` pairs; `solve()` returns an `ImmersalAnchor.Fit` once
there are at least `minimumPairs` (4) pairs whose graph points span at least
`minimumSpread` (2 m), using `ImmersalAlignment.fit(pairs:mapIDs:
minimumPairs:minimumSpread:)`, which gains those two **defaulted** parameters
so its current callers (the probe walk) are unchanged; `ty` = mean of
(graph y − session y) over the pairs, or 0 when unknown. `reset()` clears it.
A phone-camera fix at any time anchors immediately and clears the bootstrap.

The head-to-chest offset (about 0.3 m) is treated as noise, inside the gate.

## Pieces

| Piece | Change |
|---|---|
| `PositioningSource.lanyard` | new case. Every `switch` or check on the source gets an explicit lanyard branch; the `.phone` and `.glasses` branches are not edited |
| `GlassesFixFeed` (new, `Glasses/GlassesFixFeed.swift`) | frame → Immersal fix → camera pose in the graph frame, for the hybrid: claim/throttle (same `minimumInterval`, `sentFrameWidth` and `GlassesCamera` intrinsics as `GlassesPositioning`), gray encode, localizer selection through `ImmersalLocalizerFactory`, pose decode through `ImmersalPose.cameraPoseInMap` and `alignment.toGraph`; emits `onFix: (simd_float4x4, TimeInterval /* arrival, systemUptime */) -> Void`. Observable counters: `attempts`, `fixes`, `lastError`, `lastLatencyMS`, `localizerName`. `GlassesPositioning` is **not modified** |
| `PhoneImmersalLocalizer` | gains `PoseHistory` (new pure struct: `(timestamp, transform)` samples, keeps the last 2 s, `pose(at:)` returns the nearest sample within 0.5 s or nil), recorded in `consume` under a lock; `offer(glassesFix graphPose: simd_float4x4, arrivedAt: TimeInterval)` pairs the fix with `history.pose(at: arrivedAt − streamLatency)`: if the anchor has a fit → `updatePosition`; else feed the bootstrap and, when it solves, install the fit (`anchor.install(fit:)`, a new method that sets the fit and counts one fix). `streamLatency` is a settable property, read from `UserDefaults` `glasses.streamLatency` (default 0.2). `onFirstFix` fires as today |
| `NavigationViewModel` | lanyard in `startPositioning` (stop `glassesPositioning`; `startARKit(relocalize: false)`; `phoneLocalizer.start`; `glassesFeed.start`; `keepStreaming = true` and `startStreaming`; fetch maps; speak), in `currentTransform`, `localizationStatus`, `anchored(_:)`, `phoneImmersalSummary`, the push-to-talk mic choice, and `observeGlassesConnection` reading the remembered mode. `glassesFeed.onFix` → `phoneLocalizer.offer`. `glasses.onFrame` fans to `glassesPositioning.consume` **and** `glassesFeed.consume`; a consumer that is not running drops the frame at its claim, so pocket mode pays one lock per frame |
| `GlassesModePreference` (new pure helper in the view model file or `Glasses/`) | `pocket`/`lanyard` ↔ `UserDefaults`, default pocket; `source(for:)` maps to `.glasses`/`.lanyard` |
| `GlassesView` | the picker; lanyard status rows: anchored / phone fixes / glasses fixes / glasses localizer / latency stepper |

Untouched: `GlassesPositioning`, `ARNavigationManager`, `GuidanceManager`,
the beacon, authoring, field test, Android.

## Failure handling

- No alignment: refuse, spoken, stay in phone mode.
- Phone camera never matches (pointing at the floor): the glasses bootstrap
  anchors within about 2 m of walking with matches.
- Glasses never match: the phone anchors as today.
- A fix that jumps: rejected; three in a row believed (existing rule, shared
  counters).
- ARKit tracking lost: `trackingReliable` false → beacon silent, "tracking
  lost" spoken (existing).
- Glasses disconnect: phone mode, spoken (existing path).
- No pose in the history for a glasses fix (ARKit not yet tracking, or a gap
  > 0.5 s): the fix is dropped and counted in `lastError`.
- Thermal: nothing automatic; the throttles bound the load; the first real
  walk tells.

## Tests

XCTest in `AISEEBINTests`:

- `ImmersalAnchorTests` (existing file): `updatePosition` keeps yaw, moves
  translation so the session position lands on the fix; respects the jump
  gate and the three-in-a-row rule with the shared counters; returns false
  with no fit; `install(fit:)` sets the fit and counts a fix.
- `PositionPairBootstrapTests`: recovers a synthetic yaw + translation from 4
  pairs over 2 m (session points rotated and shifted); refuses 3 pairs; refuses
  a 1 m spread; `ty` is the mean height difference; reset clears.
- `PoseHistoryTests`: nearest sample within 0.5 s; nil beyond; keeps only the
  last 2 s; empty → nil.
- `GlassesModePreferenceTests`: default pocket; round-trips lanyard; maps to
  the right `PositioningSource`.
- `ImmersalAlignmentTests` (existing): unchanged and green, proving the
  defaulted parameters change nothing.
- Every existing test class unchanged and green.

Hand check on site: a lanyard walk; the diag log shows `phone-immersal`
fixes, `glasses-fix` lines, and `anchored` flipping to true from whichever
camera matched first; the live map follows the walker; the beacon's heading
follows the body.

## Out of scope

Android; clock synchronisation of the glasses PTS; a rigid head-to-chest
model; using the glasses heading for yaw; fusing orientation.
