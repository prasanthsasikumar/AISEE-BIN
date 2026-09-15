# Glasses positioning — design

**Goal.** A blind visitor wears AiSee glasses, keeps the iPhone in a pocket, and is
guided exactly as today: voice and haptics, "take me to the orchids", turn-by-turn.
The glasses camera is the only sensor that can see; the phone provides the compute,
the network and the pedometer.

**Status.** Approved in conversation on 2026-09-16. Immersal Pro account is
available. The Immersal native iOS plugin is *not* on hand yet, so localization
goes over the REST API, behind an interface the plugin can slot into later.

## What we know going in

From the 2026-09-15 probe walk (`Immersal-vs-ARKit.pdf`, `probe/`):

- Immersal REST answers in ~1.1 s median on good Wi-Fi with a 960×720 grayscale
  PNG (~600 KB). Rotation convention is settled: row-major, CV camera axes.
- 26 fixes out of 50 tries on a thin two-minute map; 1 in 25 fixes was a 2.55 m
  blunder. Accuracy ≈ 0.3 m at three reference points.
- ARKit relocalization took 44 s; Immersal's first fix took 20 s.

From `AiSeeGlassKit` (Realtek SDK 1.6.4):

- Live video: H.264, 1280×720, up to 30 fps, over the glasses' own Wi-Fi hotspot.
  Decoded frames arrive as `CVPixelBuffer` in 32BGRA.
- No IMU, no odometry, no published intrinsics.
- One button: tap / double tap / triple tap, reported as key 1 / 2 / 3.
- 16 kHz Int16 PCM microphone. Speakers over Bluetooth.
- The phone joins the glasses' hotspot while streaming, so internet is cellular.

## Constraints the design honours

1. **Nothing in the phone-mode path changes behaviour.** Chest-mount ARKit mode
   remains the default and its tests stay green.
2. **The graph stays in ARKit world-map coordinates.** The web editor, the
   authoring flow and every pure-logic test keep their frame. Glasses mode maps
   Immersal fixes *into* that frame through one stored rigid transform.
3. **A wrong fix must not be spoken as fact.** Every fix passes a plausibility
   gate before it can move the visitor.
4. **The kit is copied verbatim** from `aisee-glass-sample`, as it was into
   Hermes, so device-sequencing rules stay enforced in one place.

## Architecture

```
                    ┌──────────────────────────────┐
  AiSeeGlassKit ───▶│ GlassesPositioning           │──PoseSnapshot──▶ NavigationViewModel
  (video frames)    │  ├ GlassesFrameSampler       │  (graph frame)    (unchanged loop:
                    │  ├ ImmersalLocalizer (REST)  │                    RouteTracker,
  CMPedometer ─────▶│  ├ FixGate                   │                    GuidancePolicy…)
                    │  ├ PoseExtrapolator          │
  NavigationMap ───▶│  └ ImmersalAlignment         │
  .immersalAlignment└──────────────────────────────┘
```

`NavigationViewModel` gains a `positioningSource` of `.phone` or `.glasses`.
Every place it reads `arManager.cameraTransform` / `arManager.localizationStatus`
now goes through `currentTransform` / `localizationStatus`, which switch on the
source. In glasses mode the AR session is paused (camera is in a pocket) and the
camera stage shows the glasses feed.

### Components

**`Managers/Immersal/`** — promoted out of `Probe/`, no longer throwaway.
`ImmersalClient` (REST `/localizeb64`), `ImmersalPose` (raw pose → ARKit-convention
camera pose), `ImmersalFrameEncoder` (luma plane or BGRA → grayscale PNG, scaled
intrinsics), `ImmersalConfig` (token + map ids in `UserDefaults`, same keys the
probe used so testers keep their setup). `Probe/` keeps compiling against them.

**`Glasses/AiSeeGlassKit/`** — verbatim copy. `Vendor/RTK` frameworks linked
for `iphoneos` only; excluded from simulator builds with
`EXCLUDED_SOURCE_FILE_NAMES[sdk=iphonesimulator*]` as Hermes does. The kit's
`#else` stubs keep the simulator and the test target compiling.

**`Glasses/GlassesService`** (`@MainActor @Observable`) — owns
`AiSeeConnectionService` + `AiSeeDeviceCoordinator`, keeps the coordinator
attached across connection changes, exposes connection state, battery, live
frame, streaming flag, and routes key presses to a `GlassesKeyMap`
(fixed mapping: tap = talk, double tap = where am I, triple tap = stop).

**`Glasses/GlassesCamera`** — the intrinsics model for a camera we did not
calibrate: `width`, `height`, `focalPx`; `ox = w/2`, `oy = h/2`, `fx = fy = focal`.
Default focal 900 px for 1280×720 (≈70° horizontal). Stored in `UserDefaults`.

**`Glasses/FocalCalibration`** — self-calibration against the map. While the
wearer stands still in a mapped spot, one captured frame is sent once per
candidate focal length (600…1400 px, step 100); repeated over N frames. Score is
successes per focal; tie-break by the tightness of the returned positions
(a wrong focal that still "succeeds" scatters). Pure scoring is a testable
function; the sweep runner is thin.

**`Glasses/FixGate`** — pure. Accepts a fix if the distance from the previous
accepted fix ≤ pedometer distance walked since then + `slack` (1.5 m). The first
fix is always accepted. After `maxRejections` (3) consecutive rejections the next
fix is accepted, so a bad first anchor cannot lock the visitor out.

**`Glasses/PoseExtrapolator`** — pure. Holds the last accepted fix (graph frame
position, heading, pedometer distance at that moment). `pose(at pedometerDistance)`
returns position advanced along the fix heading by the metres walked since.
Reports `isStale` once a fix is older than 8 s: status drops to
`.limited("No fix")` and guidance pauses as it does when ARKit loses tracking.

**`Models/ImmersalAlignment`** — `{ mapIDs, yaw, tx, tz, pairCount, rmsError }`
stored as `NavigationMap.immersalAlignment` (optional; old JSON decodes).
`toGraph(_ immersalXZ)` = `R(yaw)·p + t`; `heading + yaw`. Fitted by a 2D rigid
Procrustes over (Immersal xz, ARKit xz) pairs collected during a phone probe walk
while ARKit tracking is normal and the fix passes the odometry gate. Refuses to
fit with fewer than 8 pairs or under 3 m of spread. The probe screen gets a
"Save alignment to map" action after a walk; Author → Upload carries it to the
server; the web editor already round-trips unknown fields.

**`Glasses/GlassesPositioning`** (`@MainActor @Observable`) — the pose source.
On each decoded frame: if no request in flight and ≥ 0.5 s since the last
attempt, convert to grayscale PNG (scale 1, 1280×720), send with the camera
model's intrinsics and the alignment's map ids. On success: `ImmersalPose` →
planar position + heading in Immersal frame → alignment → graph frame → `FixGate`
→ `PoseExtrapolator.anchor`. A 5 Hz timer emits `PoseSnapshot`s from the
extrapolator so the guidance loop runs at a steady cadence between fixes.
Status: `.relocalizing` until the first accepted fix, `.trackingReady` while
fresh, `.limited("No fix")` when stale, `.notStarted` when the glasses are not
streaming, `.unsupported` when the map has no alignment.

**Voice.** `VoiceCommandRecognizer` gains `append(_ buffer:)` and an
`externalInput` flag: in glasses mode the view model opens the glasses mic
through the coordinator, feeds buffers to the recognizer, and closes it when
listening ends. Speech output already allows Bluetooth A2DP, so it reaches the
glasses' speakers when they are the active route.

### UI

- ⋯ menu → **Glasses…** opens `GlassesView`: scan / connect / battery, stream
  toggle with live preview and fps, focal calibration, and the
  **Use glasses for positioning** switch (disabled until connected, streaming
  and the map has an alignment; the row says which is missing).
- Status badge reuses `LocalizationStatus`; the camera stage shows the glasses
  frame in glasses mode; the relocalizing hint reads "Look around slowly so the
  glasses can recognise the greenhouse."
- Probe screen: **Save alignment to map** after a walk, with pair count and
  RMS shown.

### Data flow per fix

```
AiSeeFrame(BGRA) ─▶ grayscale PNG ─▶ /localizeb64 (fx=fy=focal, ox=w/2, oy=h/2)
   ─▶ ImmersalRawPose ─▶ cameraPoseInMap ─▶ (x,z,heading)_imm
   ─▶ alignment ─▶ (x,z,heading)_graph ─▶ FixGate(pedometer Δ) ─▶ extrapolator
   ─▶ 5 Hz PoseSnapshot ─▶ NavigationViewModel.handle (unchanged)
```

## Error handling

- Glasses disconnect or stream termination → status `.notStarted`; guidance
  speaks "Glasses disconnected" once; positioning resumes when the stream does.
- Localization transport failures are dropped, not queued (a stale frame is worse
  than none in live guidance). Immersal "no match" simply waits for the next frame.
- Missing alignment → `.unsupported` with an explanatory row in `GlassesView`.
- `AiSeeError.deviceWedged` → the toggle turns off with the kit's message.

## Testing

Pure logic, in `AISEEBINTests`: `FixGateTests`, `PoseExtrapolatorTests`,
`ImmersalAlignmentTests` (fit recovers a planted yaw/translation, refuses thin
data, JSON round-trip with and without the field), `GlassesCameraTests`
(intrinsics scale with resolution), `FocalCalibrationTests` (scoring picks the
right focal from planted results). Existing suites stay green.

On device: build on the attached iPhone; connect glasses; stream; run focal
calibration in the mapped room; save an alignment from a phone probe walk;
switch positioning to glasses and walk to a place.

## Out of scope (deliberately)

- Immersal native on-device plugin (slot exists; needs the SDK download).
- Authoring from the glasses; a second Immersal map for outdoors; wake word.
- Replacing the chest-mount mode.
