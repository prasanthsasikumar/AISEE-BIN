# Beep guidance (heading beacon)

**Date:** 2026-10-16
**Status:** approved in conversation ("spec looks okay, go ahead and build it")

## Why

Spoken prompts arrive every few seconds at best. Between them a blind walker has
no idea whether they are still pointed along the route, and a wrong turn is only
caught at the next sentence or at the off-route warning. Blind-navigation
practice (and the advice relayed to us on 2026-10-15) is a continuous beep that
changes as the walker strays, so they can correct at once without waiting for
words. This is an **optional** mode, off by default, on iOS only: Android has no
route guidance yet.

## What the walker hears

- The beacon runs only while a route is active **and** the position is trusted:
  `trackingReliable` on the pose snapshot, which in glasses mode means the last
  fix is not stale. Otherwise it is silent. Silence always means "I don't know",
  never "you are fine"; the existing spoken "tracking lost" covers the loss.
- It aims at a point **3 m ahead along the route** (the destination when that is
  closer), measured from the walker's projection onto the current leg. Aiming at
  the next node would swing the beacon as waypoints are passed.
- **Two states with hysteresis**: off course once the bearing to the aim point
  exceeds 25°, back on course once it is within 15°. Two sounds are learnable; a
  continuous slide is not.
  - **On course:** one short high tick (≈ 880 Hz, 60 ms) every 0.6 s, centred.
  - **Off course:** a low pattern (≈ 440 Hz) every 1.2 s that mirrors the haptics
    the app already teaches: **left = two quick low ticks, right = one long low
    tone**. On stereo output (the glasses, earphones) it is also panned to that
    side; on the phone's mono speaker the pattern alone carries the side.
- **Corridor:** the moment the walker is further than `offRouteDistance` (2.5 m)
  from the leg, a one-off low three-note "boundary" earcon plays before the
  spoken "You are off route. Recalculating." and the replan. Afterwards the
  beacon aims at the new route.
- The beacon **pauses** while the app speaks (clip or synthesizer) or listens
  (push-to-talk), and stops at arrival or when navigation stops.
- With the beacon on, the periodic reassurance ("Continue straight for 12
  metres…") stretches from 12 s to 30 s. Turns, doors, node reached, arrival and
  off-route still speak as today.
- **Off by default.** Settings → "Beep guidance" toggle; voice "beeps on" /
  "beeps off" (also "beep", "beacon"). Takes effect mid-route.

## Heading between fixes (glasses mode)

`PoseExtrapolator` today holds the head direction from the last fix until the
next one; fixes arrive every one to two seconds at best and count as stale after
8 s. A beacon that ignores a turn for that long is worse than none.

New `BodyHeading` (Glasses/): `CMMotionManager` device-motion updates at ~30 Hz,
started with glasses positioning and stopped with it. Each sample integrates the
rotation rate projected on gravity (both in the device frame), which is the turn
about the vertical whatever way the phone sits in a pocket. The sign is
clockwise-positive, matching the graph heading (`atan2(forward.x, -forward.z)`,
a right turn increases it), so `turn = ∫ ω · ĝ dt` with `ĝ` the unit gravity
vector. Drift is irrelevant: every accepted fix records the current `turn`, and
between fixes `heading = fixHeading + (turn − turnAtFix)`.

Known bias: the fix gives the *head* direction, the gyro the *body*; if the
walker was looking sideways at the fix, the heading is off by that much until
the next fix. Accepted. The turn instructions ("in 3 m turn right") read the same
heading and improve with it. Phone mode is untouched: ARKit heading at 60 Hz.

If device motion is unavailable (simulator), the offset is 0 and behaviour is
today's.

## Pieces

| Piece | Kind | Does |
|---|---|---|
| `BeaconPolicy` (Managers/) | pure struct | bearing, off-route, reliable, navigating → `BeaconCue` (`.silent`, `.onCourse`, `.offCourse(side:pan:)`), hysteresis state inside |
| `RouteTracker.aimPoint(from:lookAhead:)` | method | walks the remaining polyline from the projection on the current leg |
| `BodyHeading` (Glasses/) | class + pure integrator | device motion → clockwise turn in radians |
| `PoseExtrapolator.cameraTransform(walked:headingOffset:)` | method | fix heading plus offset |
| `BeaconSynth` (Managers/) | final class | `AVAudioEngine` + `AVAudioPlayerNode` on the existing audio session, three precomputed PCM patterns, `pan` on the node; idempotent `apply(_:)`, `pause()`, `resume()`, `playBoundary()` |
| `CommandParser` | `.beacon(on: Bool)` | checked before the "stop" rule so "stop beeps" is not "stop" |
| `GuidancePolicy` | settable `progressReminderInterval` | 30 s while the beacon is on |
| `NavigationViewModel` | wiring | one `evaluate` + `apply` per snapshot after `isOffRoute`; boundary earcon on the off-route event; pause on speech / listening; `beaconEnabled` from `UserDefaults` `guidance.beacon` |
| `SettingsView` | toggle | "Beep guidance" with a one-line explanation |

`pan = clamp(bearing / 90°, −1, 1)` (negative = left). Sides: bearing < 0 → left
(matches `relativeBearing`, positive = turn right).

## Failure handling

- Engine fails to start (audio session conflict): log, beacon off, no crash.
- Audio interruption (call, Siri): on `AVAudioSession.interruptionNotification`
  ended, restart the engine and resume the current cue.
- Replan: `BeaconPolicy` state persists; the aim point comes from the new
  tracker.
- Background: `UIBackgroundModes` already contains `audio`, so the beacon keeps
  playing with the screen locked and the phone in a pocket.

## Tests

XCTest in `AISEEBINTests`:

- `BeaconPolicyTests`: silent when not navigating / not reliable / muted;
  on-course inside 15°; off-course beyond 25° with the right side; hysteresis
  between 15° and 25° keeps the previous state; pan clamps at ±1.
- `RouteTrackerTests`: aim point on a straight leg; look-ahead crossing a node;
  remaining route shorter than the look-ahead gives the destination; position
  before the leg start projects to the start.
- `GlassesPositioningLogicTests`: extrapolator transform with a heading offset
  (anchor, turn, re-anchor resets the offset).
- `BodyHeadingTests`: integration on synthetic samples; a left turn is negative;
  the same turn gives the same sign with the phone upside down; zero when
  rotation is about a horizontal axis.
- `CommandParserTests`: "beeps on", "turn off the beeps", "beacon on", and that
  "stop beeps" is not `.stop`.
- `GuidancePolicyTests`: the reminder interval change applies.

`BeaconSynth` is checked by hand on the phone and through the glasses: left and
right turns swap sides; silence on tracking loss; pause during speech; works
screen-locked in a pocket; and one glasses walk logging fix heading against gyro
heading in `immersal-diag.log` to confirm the sign.

## Out of scope

Android; spatial audio (HRTF); a volume setting; encoding distance in the beep.
