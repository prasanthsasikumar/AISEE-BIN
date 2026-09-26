# On-device Immersal localization

**Date:** 2026-09-26
**Status:** approved in conversation ("lets make sure we use offline - do what is needed")

## Why

Every Immersal fix today is a round trip to `api.immersal.com/localizeb64`, on the
phone and on the glasses. Without a network the phone never anchors in an
editor-drawn or Immersal-built map, and the glasses have no position at all. A
visitor's phone in a pocket on greenhouse Wi-Fi, or on cellular next to the
glasses' hotspot, cannot be a thin client. Immersal's native plugin localizes
against an embedded map file with no server and no token, so the fixes can be
computed on the phone.

## What was verified before this design (2026-09-26)

- Immersal publishes the native iOS library, `libPosePlugin.a`, in its public
  Unity SDK repository (`github.com/immersal/imdk-unity`, tag `2.4.0`,
  `Runtime/Plugins/iOS/`). arm64 device slice only, min iOS 12, 9.8 MB, C++
  inside (`-lc++`), no framework dependencies beyond libSystem and libdispatch.
  The developer-portal download endpoint is gated on an EULA flag that the Pro
  account (userId 20806) still reports as **not accepted**; the GitHub copy is
  not gated. The SDK licence header forbids redistribution, so the library is
  fetched at build time rather than committed.
- The plugin's C header (`PosePlugin.h`) is in Immersal's MIT-licensed iOS
  samples repository and matches the SDK 2.4.0 C# bindings: `LocalizeInfo` is
  `{int handle; float3 position; float4 rotation(xyzw); int confidence}`, 36 bytes.
- The macOS build of the same plugin loads map 151670 (built by today's server,
  core `1.27.0-260828`) with no token: handle 0, 3981 points, 34 ms. A localize
  call on a 960x720 gray frame returns in ~50 ms on an M-series Mac.
- The SDK's own REST code (`ServerLocalization.cs`) builds `r00..r22` row-major
  into the same `LocalizeInfo` the native call returns, so the native
  quaternion is the REST rotation matrix in the convention this app confirmed on
  2026-09-15 (`ImmersalPoseConvention.rowMajorCVCamera`). Nothing downstream of
  `ImmersalRawPose` changes.
- Map binaries download with the Pro token: `GET /map?token&id` returns the
  `.bytes` file (LZMA, ~470 KB for a 100-image map).

## Scope

In: on-device localization for phone-in-Immersal-map and glasses positioning;
a local cache of map binaries filled whenever the app is online; automatic
choice between on-device and cloud with the reason visible in diagnostics.

Out: Author mode's capture and map construction (Immersal builds maps on its
servers; that stays online), the probe screen's REST measurements, any change
to the alignment model, fix gate, anchor, or pedometer dead reckoning.

## Design

### Vendor/Immersal

```
Vendor/Immersal/
  PosePlugin.h          from immersal-sdk-ios-samples (MIT), with the licence note
  module.modulemap      module PosePlugin { header "PosePlugin.h" export * }
  fetch.sh              downloads libPosePlugin.a from imdk-unity tag 2.4.0,
                        verifies its sha256, no-op when present
  libPosePlugin.a       gitignored
  ImmersalNativeStubs.c compiled for the simulator only: every icv* symbol
                        returns -1 / an empty struct, so the test target links
```

`project.yml` gains, for `sdk=iphoneos*` only: `LIBRARY_SEARCH_PATHS` +=
`$(SRCROOT)/Vendor/Immersal`, `OTHER_LDFLAGS` += `-lPosePlugin -lc++`. Both
SDKs get `SWIFT_INCLUDE_PATHS` += `$(SRCROOT)/Vendor/Immersal` for the module
map. A pre-build script phase runs `fetch.sh` for device builds so an archive
on a fresh clone does not fail at link time. The stub file is excluded from
device builds with `EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]`.

The weak-symbol alternative (stubs in every build, `-force_load` on device)
was tested and works, but conditional compilation is simpler and cannot
silently shadow the real library.

### ImmersalNative (Managers/Immersal/ImmersalNative.swift)

A `final class`, one shared instance, `@unchecked Sendable` with an `NSLock`.
The plugin's thread safety is undocumented; the Unity SDK issues one localize
at a time from a worker thread, so this wrapper serialises every call.

- `static var isAvailable: Bool` — `false` on the simulator, `true` on device.
- `func load(mapID: Int, data: Data) throws -> Void` — `icvLoadMap` on the
  bytes; keeps `mapID -> handle` and the reverse. Loading an id already loaded
  is a no-op.
- `func unload(all:)`, `func unload(mapID:)` — `icvFreeMap`.
- `var loadedMapIDs: [Int]`.
- `func localize(_ frame: GrayFrame, intrinsics: Intrinsics) -> ImmersalLocalizeResult`
  — `icvLocalize` with `n = 0` (all loaded maps), `channels = 1`, `solverType = 0`,
  identity rotation. `handle >= 0` becomes `success` with `mapID` from the
  table and `pose` an `ImmersalRawPose` whose `r` is the row-major matrix of
  the returned quaternion. `latency` is wall time, `requestBytes` the pixel
  count, `error` is `"none"` on success and `"no match"` otherwise.
- On first use sets `LocalizationMaxPixels` to `960 * 720`, the size the
  cloud path already sends, so a full 1920x1440 ARKit plane costs the same as
  today's PNG.

`GrayFrame` is `{ pixels: Data (tightly packed, width*height), width, height }`.
`Intrinsics` is the existing `(fx, fy, ox, oy)` tuple.

### One localizer interface for both callers

```swift
protocol ImmersalLocalizer: Sendable {
    var name: String { get }          // "on device" | "cloud"
    func localize(_ frame: GrayFrame, intrinsics: Intrinsics) async -> ImmersalLocalizeResult
}
```

- `CloudImmersalLocalizer` wraps `ImmersalClient`: encodes the gray frame to
  PNG (new `ImmersalFrameEncoder.png(from: GrayFrame)`) and posts it. Behaviour
  identical to today.
- `NativeImmersalLocalizer` wraps `ImmersalNative` and runs the call on a
  detached task so the main actor never blocks.
- `ImmersalLocalizerFactory.make(mapIDs:, cache:) -> ImmersalLocalizer` picks
  native when `ImmersalNative.isAvailable` and every id is in the cache and
  loads successfully, else cloud. It writes one `DiagnosticsLog` line naming the
  choice and, for cloud, the reason (`simulator`, `map 151670 not cached`,
  `load failed`).

`ImmersalFrameEncoder` gains the two producers of `GrayFrame`:
`packedLuma(from: LumaPlane, maxWidth:)` (drops row padding, halves like today)
and `gray(from: BGRAImage, targetWidth:)` (the same CoreGraphics draw that
makes the glasses PNG today, returning the pixels instead). The PNG helpers
stay for the diagnostics sample files and the cloud path.

`PhoneImmersalLocalizer` and `GlassesPositioning` stop building
`ImmersalClient` themselves. Each takes an `ImmersalLocalizer` from the factory
at `start` and exposes `localizerName` for the UI. The glasses class keeps its
injectable closure for tests, retyped to the gray frame.

### ImmersalMapCache (Managers/Immersal/ImmersalMapCache.swift)

Files at `Documents/immersal-maps/<id>.bytes`.

- `contains(_ id)`, `data(for: id)`, `missing(from ids: [Int]) -> [Int]`.
- `fetch(_ ids: [Int], token: String, session:) async throws` — `GET
  /map?token=&id=` per id, written atomically; an HTTP error or a body under
  1 KB (Immersal's JSON error) throws with Immersal's reason.
- `prune(keeping ids: [Int])`.

Filled from two places in `NavigationViewModel`:

1. `install(_:)` — after the graph is saved, if it has an alignment, fetch the
   missing ids (progress folded into the last 10 % of the sync bar). A failure
   here is logged and does not fail the install: the cloud path still works.
2. `startPositioning()` — if the map has an alignment and ids are missing, kick
   off a background fetch, then restart the localizer when it lands so the
   session upgrades from cloud to on-device without user action.

`prune` runs after a successful install with the current map's ids, so
switching maps in the picker does not accumulate binaries.

### Status surfaces

- Glasses screen: the existing Fixes/Latency rows gain a "Localizer" row
  (`on device` / `cloud`).
- Debug overlay: `trackingState` for the phone-in-Immersal case becomes
  `… · immersal on device 3/7` (or `cloud`).
- Settings: a line under the map ids showing which ids are cached, with a
  "Download maps now" button that calls `fetch` for the current ids.

### Error handling

- Native load failure (corrupt file, wrong version): log, delete the file, fall
  back to cloud for this session; the next online start re-fetches.
- No network and no cached maps: today's behaviour (cloud attempts fail with a
  transport error; status shows relocalizing). Nothing new to handle.
- Token missing: on-device needs none. The cache fetch needs one and reports
  the existing "No Immersal token" hint.

### Testing

Unit tests (simulator, stubs linked):

- `ImmersalNativePoseTests`: a quaternion round-trips through the row-major
  matrix into `ImmersalPose.cameraPoseInMap` and matches the matrix built
  directly from `simd_quatf`; a fix on the simulator stub reports `success ==
  false`, `error == "no match"`.
- `ImmersalFrameEncoderTests`: `packedLuma` drops row padding and halves;
  `gray(from:targetWidth:)` returns `width*height` bytes.
- `ImmersalMapCacheTests`: path naming, `missing(from:)`, a stubbed fetch
  writes the file, a JSON error body throws and writes nothing, `prune`.
- `ImmersalLocalizerFactoryTests`: chooses cloud with the reason when
  unavailable or uncached.

On device, owed after the build: run the phone in map 151670/151683 in
airplane mode and see fixes; the glasses the same way on cellular off. The
scratchpad harness (`harness.swift`) can compare native and REST output on
the same PNG once a frame from a mapped space is available.

### App Store / privacy consequence

With this in place, visitor-side positioning sends no camera images anywhere
once the map is cached. Author mode still uploads scan frames to Immersal to
build a map; the privacy policy must still say so.
