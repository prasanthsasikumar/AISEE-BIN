# Ray-Ban Meta glasses support

**Date:** 2026-11-12
**Status:** approved in conversation 2026-11-12 (phone talk button for now; answers must serve sighted and non-sighted visitors)

## Why

Glasses mode only works with the AiSee glasses (Realtek SDK, `AiSeeGlassKit`).
Prasanth wants the same experience on Ray-Ban Meta glasses. In his words, a
visitor wearing them with the phone put away should get:

1. **Navigation.**
2. **Answers to questions** asked while looking at something ("what is this?"),
   answered with relevance to the place they are in.

He has a Ray-Ban Meta **Gen 1** to test with, linked to a Meta developer
account. The work must land on `main` and on `aria-hloc-localizer`.

## Goals

- Pick Ray-Ban Meta as the glasses on the Glasses screen and use every existing
  glasses feature with them: pocket mode, lanyard mode, focal calibration, the
  probe/alignment tools, usage logging.
- Ask a free-form question by voice while navigating, with a picture from the
  glasses and the map context, and hear the answer through the glasses.
- AiSee glasses behave exactly as they do today.

## Non-goals

- Android. The Android prototype stays AiSee-only.
- The NUS target (`NUSOpenHouse`): it has no glasses code today and gets none.
- Meta Ray-Ban Display screen content, "Hey Meta" voice launch, Meta's own
  speech/motion modules.
- Public App Store release. Meta's toolkit (1.0.1) is a developer preview;
  publishing to the general public is not open yet.

## Anti-goals

- Breaking or slowing the AiSee path, phone mode, authoring or the NUS build.
- Sending the visitor to the Meta AI app by surprise in the middle of a walk.
  App switches (registration, camera permission) happen only from a button on
  the Glasses screen.

## What Meta's toolkit gives us (checked 2026-11-12, version 1.0.1)

Swift package `https://github.com/facebook/meta-wearables-dat-ios`, modules
`MWDATCore` (registration, devices, sessions, permissions) and `MWDATCamera`
(stream and in-stream photo). A local copy of the repo with its guides is the
reference; the full API reference is at
`https://wearables.developer.meta.com/llms.txt?full=true`.

- Needs iOS **17.2** (the project is on 17.0), the Meta AI app on the phone,
  and, for now, Developer Mode switched on for the glasses in Meta AI.
- Flow: `Wearables.configure()` at launch → `startRegistration()` (opens Meta
  AI, returns through our URL scheme, `handleUrl`) → `requestPermission(.camera)`
  (opens Meta AI again) → `createSession(deviceSelector:)` → `start()` → wait
  for `.started` → `addCamera(config:)` → `camera.stream.start()`.
- Video: portrait frames, `.high` 720×1280, `.medium` 504×896, `.low` 360×640;
  2, 7, 15, 24 or 30 fps; `.raw` codec gives decoded frames
  (`VideoFrame.sampleBuffer`, `makeUIImage()`). It travels over Bluetooth
  Classic, so there is no glasses Wi-Fi hotspot and the phone keeps its normal
  internet. Lower resolution and frame rate give better-looking frames.
- `stream.capturePhoto(format: .jpeg)` takes a still while streaming.
- The glasses can pause or stop a session on their own (taken off, folded,
  "Hey Meta", another app, heat, low battery).
- The capture button reaches apps only through the experimental `MWDATInputs`
  module, which has to be enabled for the app in the Wearables Developer Center.
- Sound: the glasses are an ordinary Bluetooth headset to iOS. Speech and beeps
  already go wherever iOS routes audio.

## Behaviour

### Choosing the glasses

The Glasses screen gets a picker at the top: **AiSee** | **Ray-Ban Meta**,
remembered in `UserDefaults` (`glasses.kind`, values `aisee` | `rayban`,
default `aisee`). Everything under it shows the chosen kind. A user who never
touches the picker sees no change.

With Ray-Ban Meta chosen, the connection section shows, in order, only the step
that is still missing:

1. "Meta AI app is not installed" (with nothing to tap), or
2. **Connect to Meta AI** (registration; opens Meta AI and comes back), then
3. **Allow camera** (opens Meta AI and comes back), then
4. the glasses' name, battery, and worn/folded state, or "Glasses not in reach".

"Connected" for the rest of the app (`GlassesService.isConnected`) means:
registered, camera allowed, and a glasses device currently linked. When that
becomes true, positioning switches to the remembered glasses mode (pocket or
lanyard) exactly as it does when AiSee glasses connect.

Losing the glasses, Ray-Ban Meta only (AiSee keeps its immediate fallback):

- **Link lost** (no device linked) for more than 10 s: "Glasses disconnected.
  Using the phone camera." and back to phone mode. A shorter drop is ridden
  out on step counting without speaking.
- **Session paused or stopped while still linked** (taken off, "Hey Meta",
  another app): never falls back to the phone. Step counting carries on; after
  10 s the app says "Glasses camera paused." once, and "Glasses camera back."
  when frames return. A stopped session is recreated when the device allows.

The AiSee-only controls (scan list, stream tuning for the Realtek encoder,
hotspot handling) are hidden for Ray-Ban Meta. Ray-Ban Meta gets its own two
stream settings: resolution (default High) and frame rate (default 7 fps;
positioning uses at most two frames a second, and a low rate keeps each frame
sharp). Preview, Start/Stop stream, Capture still and Calibrate focal length
work for both kinds.

### Positioning

Ray-Ban frames are turned into the existing frame value (`AiSeeFrame`: pixel
buffer + timestamp) and go through the same `onFrame` path, so
`GlassesPositioning`, `GlassesFixFeed`, the frame selector, the fix gate, the
pedometer and gyro heading are reused untouched in logic.

Two things differ and must be handled:

- **Portrait frames.** `GlassesCamera` assumes 1280 px wide landscape. The
  focal length is to be defined against the **long edge** (1280 px reference),
  so `intrinsics(width:height:)` scales by `max(width, height) / 1280`. For
  AiSee frames this gives the same numbers as today.
- **A different lens.** The focal length is stored per kind
  (`glasses.camera.focalPx` stays AiSee's; `glasses.camera.focalPx.rayban` is
  new, default 900 until calibrated). The existing focal sweep is how the real
  value is found, on site, against a map. Widen the sweep if the Gen 1 lens
  turns out wider than 600–1400 px covers.

The frame encoder and the on-device/cloud localizers must accept 720×1280
input; Immersal itself is known to be rotation-invariant and fine at other
sizes (project notes, 2026-09-24).

### Asking a question

Today free-form questions exist only in Explore mode and always use the
phone's camera. This changes in two ways:

- **Picture source.** When the glasses are the positioning source and are
  connected (either kind), the picture for a question is the newest glasses
  frame, as a JPEG no larger than 768 px on its long edge (same limits as the
  phone picture). Otherwise the phone's ARKit frame, as today. This applies in
  Explore mode too.
- **Questions in Navigate.** Push-to-talk already exists (screen button; AiSee
  temple tap). The parser order becomes:
  1. The fixed phrases as today (where am I, what's nearby, repeat, beeps
     on/off, stop), matched as whole phrases so "can you describe that again"
     is not "repeat" and "is there a toilet nearby" is not "what's nearby".
  2. An explicit go-there request (take me to, go to, navigate to, bring me
     to, find, where is/are + a place name) → navigate, as today.
  3. A question opener (what, what's, who, which, why, how, when, is, are,
     does, do, can, tell me, describe, explain) → question, **even when it
     names a place**: "what is the Orchid Display?" is answered, not routed.
  4. A bare place name ("orchids") → navigate, as today.
  5. Anything else → "I didn't catch that", as today.
  Existing parser tests that conflict with rule 3 are updated, and each rule
  gets tests. The question goes to the same
  service Explore uses (`ExploreClient.ask`: picture, map slug, nearby places
  from position and heading, venue info, recent turns) and the answer is spoken
  sentence by sentence as it streams. A turn instruction or a safety cue may
  interrupt the answer; the answer never interrupts them. The asking code in
  `ExploreViewModel.send` is pulled out into one shared piece so both modes
  use it.

Starting a question on Ray-Ban Meta: the push-to-talk button on the phone
screen (Prasanth, 2026-11-12: "for now lets use phone"). The capture button
needs the experimental `MWDATInputs` capability enabled for the app in the
Wearables Developer Center; no project exists there yet, and Prasanth will
apply. It is out of this version; the kit keeps a key-press callback so it
can be added later.

Listening: for Ray-Ban Meta the recognizer uses the phone's normal audio
input, with the Bluetooth headset microphone allowed while listening and the
audio session put back to playback-only afterwards (AiSee had a "call ended"
announcement problem when the headset profile stayed on; do not leave it on).
If the glasses microphone cannot be selected, the phone microphone is used.

### The answering service

The proxy's prompt (`server/explore/lib.mjs`) is written for a sighted Flower
Dome visitor holding a phone. Prasanth: it must serve sighted and non-sighted
people, on either kind of glasses or the phone. The request gains three
optional fields:

- `audience`: `"sighted"` (default) or `"nonsighted"`. It follows the mode the
  visitor is in, not the hardware: Explore is the sighted mode, Navigate is
  the blind / low-vision mode. For `nonsighted` the answer describes what is
  in view plainly (what it is, colour, size, where it sits relative to the
  visitor), never says "look at" or "as you can see", and stays short for
  speech.
- `camera`: `"phone"` (default) or `"glasses"`, so the wording fits ("what you
  are facing" rather than "what you point the camera at").
- `venue`: the map's display name, replacing the hard-coded Flower Dome when
  present.

Old app builds keep working because all three are optional. The proxy is
redeployed to the VPS as part of this work (backup of the old files first).

## Structure

- `AISEEBIN/Glasses/MetaGlassKit/` (new): everything that imports `MWDATCore`
  / `MWDATCamera` lives here, behind `#if canImport(MWDATCore)` with a stub
  path so the test target and any build without the package compile. It
  exposes a small vendor-free surface: status (not installed / needs
  registration / needs camera permission / no device / ready / paused),
  device name and battery, `startStreaming`, `stopStreaming`, `captureStill`,
  a frame callback delivering `AiSeeFrame`, and an optional key-press callback.
  The status logic that can be written without the SDK (how the raw states
  combine into one status, the 10 s disconnect grace) is a pure type with unit
  tests.
- `GlassesService` keeps its public shape and routes to AiSee or Ray-Ban by
  `glasses.kind`. Views stop reaching into `glasses.connection` directly where
  that is AiSee-specific.
- App start: `Wearables.configure()` once; `.onOpenURL` forwards URLs carrying
  the `metaWearablesAction` query item to `Wearables.shared.handleUrl`.
- `project.yml`: the package (pinned to 1.0.1), products `MWDATCore` and
  `MWDATCamera` on the `AISEEBIN` target only; deployment target 17.2;
  `xcodegen generate` afterwards.
- `Info.plist` (AISEEBIN target): URL scheme `aiseebin`; the `MWDAT`
  dictionary (`AppLinkURLScheme` `aiseebin://`, `MetaAppID` `$(META_APP_ID)`,
  `ClientToken` `$(META_CLIENT_TOKEN)`, `TeamID` `$(DEVELOPMENT_TEAM)`);
  background modes `bluetooth-peripheral` and `external-accessory` added to
  the existing two; `UISupportedExternalAccessoryProtocols`
  `com.meta.ar.wearable`; `NSLocalNetworkUsageDescription`; `NSBonjourServices`
  `_bonjour._tcp`. Meta's sample also lists the `processing` background mode;
  add it only if the SDK refuses to configure without it, because Apple then
  also demands `BGTaskSchedulerPermittedIdentifiers`.
- Usage log: existing glasses events gain `kind`; registration, permission,
  session pause/stop and stream errors are logged as text.

## Testing

- Unit tests (simulator): kind persistence; long-edge intrinsics (AiSee
  numbers unchanged, portrait case); per-kind focal storage; the status
  reducer and disconnect grace; question detection in `CommandParser`
  (commands still win; non-questions still unknown); picture-source choice.
- The full existing suite stays green on the `nus-test` simulator, and both
  app targets build.
- Not verifiable here, owed on Prasanth's Gen 1: registration and permission
  round trip, stream start, focal sweep against a map, a pocket walk, a
  question, capture-button input, the glasses microphone, and whether the
  stream survives the phone being locked in a pocket.

## Distribution

On Prasanth's own glasses, Developer Mode is enough and `META_APP_ID` can stay
empty. For other testers the app must exist in the Wearables Developer Center
with a release channel and the testers invited; the archive step then passes
`META_APP_ID` and `META_CLIENT_TOKEN` (kept outside the repo, like the Immersal
token). No TestFlight build is cut as part of this work until Prasanth asks.

## Branches

Build on a feature branch from `main`, merge to `main`, then merge `main` into
`aria-hloc-localizer` (worktree `../AISEE-BIN-aria`, one commit of its own).
That merge also brings main's three newer commits (beeps under the voice,
route tidy-up, web Tidy button) onto the hloc branch. Both branches must build
and pass tests before pushing.

## Calls made by Claude, not by Prasanth

- iPhone app only; NUS target and Android left out.
- Picker on the Glasses screen rather than automatic detection.
- Questions in Navigate start from push-to-talk and are recognised by their
  opening words.
- The question picture is the newest stream frame rather than a separate
  full-quality photo (faster, and does not interrupt the stream).
- Default stream: High resolution at 7 fps.
- 10 s grace before falling back to the phone, Ray-Ban only; a paused camera
  never falls back.
- Question openers beat place names in the voice parser.
- The answering service gets an audience and a venue name.
- Merging `main` into the hloc branch rather than cherry-picking one commit.

## Left to the builder

File and type names inside `MetaGlassKit`, the exact shape of the shared
asking piece, layout details of the Glasses screen, and how the session is
recreated after the glasses stop it.
