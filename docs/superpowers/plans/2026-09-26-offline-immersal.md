# On-device Immersal Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phone and glasses positioning compute Immersal fixes on the phone from cached map binaries, with the cloud endpoint only as a fallback.

**Architecture:** Immersal's `libPosePlugin.a` is linked for device builds (C stubs on the simulator) behind a serialised Swift wrapper that returns the app's existing `ImmersalLocalizeResult`. Both callers go through one `ImmersalLocalizer` protocol chosen by a factory: native when every map id is cached and loads, cloud otherwise. A map cache downloads `.bytes` files from `GET /map` whenever the app installs a map or starts positioning online.

**Tech Stack:** Swift 5 / iOS 17, XcodeGen, XCTest on the iOS simulator, Immersal SDK 2.4.0 native plugin.

**Spec:** `docs/superpowers/specs/2026-09-26-offline-immersal-design.md`

## Global Constraints

- Nothing downstream of `ImmersalRawPose` changes; the confirmed convention is `ImmersalPoseConvention.rowMajorCVCamera`.
- `libPosePlugin.a` is never committed (SDK licence forbids redistribution); it is fetched from `https://raw.githubusercontent.com/immersal/imdk-unity/2.4.0/Runtime/Plugins/iOS/libPosePlugin.a`, sha256 pinned in `fetch.sh`.
- The library is arm64 device only: link it for `sdk=iphoneos*` only; the simulator compiles `ImmersalNativeStubs.c`.
- The plugin's thread safety is undocumented: every native call is serialised behind one lock.
- Author mode's Immersal capture stays online; nothing in this plan touches `ImmersalScanRecorder`.
- Tests run with: `xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AISEEBINTests/<Class>` (the shim note in memory: if `xcodebuild` fails on the licence, use the raw toolchain type-check).
- Regenerate the project after editing `project.yml`: `xcodegen generate`, and commit `AISEE-BIN.xcodeproj/project.pbxproj`.

## Review Focus

1. ARKit luma planes with row padding (`rowBytes > width`): packed pixels must drop the padding or every fix is garbage. Test in Task 2.
2. A cached map file that is truncated or from a future plugin version: `icvLoadMap` returns -1; the factory must fall back to cloud and delete the file, not crash. Test in Task 4 (stub returns -1 for everything, which is exactly this case).
3. A map's alignment lists two ids and only one is cached: must use cloud, not localize against half the maps. Test in Task 4.
4. `GET /map` answering HTTP 200 with a small JSON error body (`{"error":"auth"}`): the cache must not write it as a map. Test in Task 5.
5. A fix arriving after `stop()` or after a restart with a different map: generation guard already exists in both callers; keep it and do not reorder the `defer { claim.release() }`.

---

### Task 1: Vendor the plugin and make both SDKs build

**Files:**
- Create: `Vendor/Immersal/PosePlugin.h` (copy of the MIT header from immersal-sdk-ios-samples, with a licence comment)
- Create: `Vendor/Immersal/module.modulemap`
- Create: `Vendor/Immersal/fetch.sh` (executable)
- Create: `Vendor/Immersal/ImmersalNativeStubs.c`
- Create: `Vendor/Immersal/README.md`
- Modify: `project.yml`, `.gitignore`
- Regenerate: `AISEE-BIN.xcodeproj`

**Interfaces:**
- Produces: Swift module `PosePlugin` exposing `icvLoadMap`, `icvFreeMap`, `icvLocalize`, `icvPointsGetCount`, `icvSetInteger`, `icvGetInteger`, and `struct LocalizeInfo`.

- [ ] **Step 1: module map**

```
module PosePlugin {
    header "PosePlugin.h"
    export *
}
```

- [ ] **Step 2: fetch.sh**

```bash
#!/bin/sh
# Downloads Immersal's native iOS library for device builds. The SDK licence
# does not allow redistributing it, so it is not in the repo.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$DIR/libPosePlugin.a"
URL="https://raw.githubusercontent.com/immersal/imdk-unity/2.4.0/Runtime/Plugins/iOS/libPosePlugin.a"
SHA="<sha256 of the downloaded file, computed in this task>"
if [ -f "$LIB" ] && [ "$(shasum -a 256 "$LIB" | cut -d' ' -f1)" = "$SHA" ]; then exit 0; fi
echo "Fetching libPosePlugin.a (Immersal SDK 2.4.0)"
curl -fsSL -o "$LIB.tmp" "$URL"
GOT="$(shasum -a 256 "$LIB.tmp" | cut -d' ' -f1)"
[ "$GOT" = "$SHA" ] || { echo "sha256 mismatch: $GOT" >&2; rm -f "$LIB.tmp"; exit 1; }
mv "$LIB.tmp" "$LIB"
```

- [ ] **Step 3: simulator stubs** — every function the Swift wrapper calls, returning failure:

```c
#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include "PosePlugin.h"
int icvLoadMap(const char *p) { (void)p; return -1; }
int icvFreeMap(int h) { (void)h; return 0; }
int icvPointsGetCount(int h) { (void)h; return 0; }
int icvGetInteger(const char *p) { (void)p; return -1; }
int icvSetInteger(const char *p, int v) { (void)p; (void)v; return -1; }
struct LocalizeInfo icvLocalize(int n, int *handles, int w, int h, float *k, void *px, int c, int s, float *r) {
    (void)n; (void)handles; (void)w; (void)h; (void)k; (void)px; (void)c; (void)s; (void)r;
    struct LocalizeInfo info = {0}; info.handle = -1; return info;
}
#endif
```

- [ ] **Step 4: project.yml** — add to `settings.base`:

```yaml
    SWIFT_INCLUDE_PATHS: "$(inherited) $(SRCROOT)/Vendor/Immersal"
    "LIBRARY_SEARCH_PATHS[sdk=iphoneos*]": "$(inherited) $(SRCROOT)/Vendor/Immersal"
    "OTHER_LDFLAGS[sdk=iphoneos*]": "$(inherited) -lPosePlugin -lc++"
```

Keep the existing `"SWIFT_INCLUDE_PATHS[sdk=iphoneos*]"` line but fold `Vendor/Immersal` into both. Add to the app target: a source entry `- path: Vendor/Immersal/ImmersalNativeStubs.c` with `"EXCLUDED_SOURCE_FILE_NAMES[sdk=iphoneos*]": ImmersalNativeStubs.c` on the target, and a `preBuildScripts` entry running `"$SRCROOT/Vendor/Immersal/fetch.sh"` named "Fetch Immersal plugin" with `basedOnDependencyAnalysis: false`. Add `Vendor/Immersal/libPosePlugin.a` to `.gitignore`.

- [ ] **Step 5: run `xcodegen generate`, then build for both SDKs**

```
xcodebuild build -project AISEE-BIN.xcodeproj -scheme AISEEBIN -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
xcodebuild build -project AISEE-BIN.xcodeproj -scheme AISEEBIN -destination 'generic/platform=iOS' -allowProvisioningUpdates -quiet
```

Expected: both succeed; the device link pulls in the real symbols (check with `nm` on the built binary for `_icvLocalize` being defined, `T`).

- [ ] **Step 6: commit** `Vendor/Immersal`, `project.yml`, `.gitignore`, `project.pbxproj`.

---

### Task 2: GrayFrame and the encoder's packed producers

**Files:**
- Create: `AISEEBIN/Managers/Immersal/GrayFrame.swift`
- Modify: `AISEEBIN/Managers/Immersal/ImmersalFrameEncoder.swift`
- Test: `AISEEBINTests/ImmersalFrameEncoderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct GrayFrame: Sendable, Equatable { var pixels: Data; var width: Int; var height: Int }
  typealias CameraIntrinsics = (fx: Float, fy: Float, ox: Float, oy: Float)
  extension ImmersalFrameEncoder {
      static func packedLuma(from plane: LumaPlane, factor: Int = downscale) -> GrayFrame?
      static func gray(from image: BGRAImage, targetWidth: Int) -> GrayFrame?
      static func png(from frame: GrayFrame) -> Data?
  }
  ```

- [ ] **Step 1: failing tests**

```swift
func testPackedLumaDropsRowPaddingAndHalves() {
    // 4x2 image, rows padded to 8 bytes; pixel value = column index
    var bytes = Data(count: 16)
    for row in 0..<2 { for col in 0..<4 { bytes[row * 8 + col] = UInt8(col * 10) } }
    let plane = ImmersalFrameEncoder.LumaPlane(bytes: bytes, width: 4, height: 2, rowBytes: 8)
    let full = ImmersalFrameEncoder.packedLuma(from: plane, factor: 1)!
    XCTAssertEqual(full.width, 4); XCTAssertEqual(full.height, 2)
    XCTAssertEqual(Array(full.pixels), [0, 10, 20, 30, 0, 10, 20, 30])
    let half = ImmersalFrameEncoder.packedLuma(from: plane, factor: 2)!
    XCTAssertEqual(half.width, 2); XCTAssertEqual(half.height, 1)
    XCTAssertEqual(half.pixels.count, 2)
}
func testGrayFromBGRAHasWidthTimesHeightBytes() {
    let image = ImmersalFrameEncoder.BGRAImage(bytes: Data(repeating: 200, count: 8 * 4 * 4), width: 8, height: 4, rowBytes: 32)
    let g = ImmersalFrameEncoder.gray(from: image, targetWidth: 4)!
    XCTAssertEqual(g.width, 4); XCTAssertEqual(g.height, 2); XCTAssertEqual(g.pixels.count, 8)
}
func testPNGFromGrayFrameDecodesToSameSize() {
    let frame = GrayFrame(pixels: Data(repeating: 7, count: 6), width: 3, height: 2)
    let png = ImmersalFrameEncoder.png(from: frame)!
    XCTAssertEqual(UIImage(data: png)?.size, CGSize(width: 3, height: 2))
}
```

- [ ] **Step 2: run, expect compile failure** (types missing).
- [ ] **Step 3: implement.** `packedLuma` copies row by row for factor 1 and draws through a gray `CGContext` for factor > 1 (reuse the existing `CGImage` construction; read the context's `data` back into `Data`, honouring `bytesPerRow`). `gray(from:targetWidth:)` is the body of `grayscalePNG(from:targetWidth:)` minus the PNG step. `png(from:)` wraps `GrayFrame` in a `CGImage` and returns `UIImage.pngData()`.
- [ ] **Step 4: run tests, expect PASS.** Commit.

---

### Task 3: ImmersalNative wrapper and NativeImmersalLocalizer

**Files:**
- Create: `AISEEBIN/Managers/Immersal/ImmersalNative.swift`
- Create: `AISEEBIN/Managers/Immersal/ImmersalLocalizer.swift` (protocol + native + cloud implementations)
- Test: `AISEEBINTests/ImmersalNativeTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol ImmersalLocalizer: Sendable {
      var name: String { get }
      func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) async -> ImmersalLocalizeResult
  }
  final class ImmersalNative: @unchecked Sendable {
      static let shared: ImmersalNative
      static var isAvailable: Bool           // false on the simulator
      var loadedMapIDs: [Int]
      func load(mapID: Int, data: Data) -> Bool
      func unload(mapID: Int)
      func unloadAll()
      func localize(_ frame: GrayFrame, intrinsics: CameraIntrinsics) -> ImmersalLocalizeResult
      static func rawPose(position: SIMD3<Float>, rotation: simd_quatf) -> ImmersalRawPose
  }
  struct NativeImmersalLocalizer: ImmersalLocalizer   // name "on device"
  struct CloudImmersalLocalizer: ImmersalLocalizer    // name "cloud"; init(token:mapIDs:session:)
  ```

- [ ] **Step 1: failing tests**

```swift
func testRawPoseFromQuaternionMatchesMatrixBuiltDirectly() {
    let q = simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.1)))
    let raw = ImmersalNative.rawPose(position: SIMD3(1, 2, 3), rotation: q)
    let expected = simd_float3x3(q)
    // r is row-major: r[row*3+col]; columns.c[r] is column c, row r
    for row in 0..<3 { for col in 0..<3 {
        XCTAssertEqual(raw.r[row * 3 + col], expected[col][row], accuracy: 1e-5)
    } }
    XCTAssertEqual(raw.px, 1); XCTAssertEqual(raw.pz, 3)
    // and the existing decoder accepts it
    XCTAssertNotNil(ImmersalPose.cameraPoseInMap(raw))
}
func testSimulatorStubReportsNoMatchWithoutCrashing() {
    let native = ImmersalNative()
    XCTAssertFalse(native.load(mapID: 1, data: Data(repeating: 0, count: 64)))
    let r = native.localize(GrayFrame(pixels: Data(count: 4), width: 2, height: 2), intrinsics: (1, 1, 1, 1))
    XCTAssertFalse(r.success); XCTAssertEqual(r.error, "no match"); XCTAssertNil(r.mapID)
}
func testCloudLocalizerNameAndTransportErrorShape() async {
    let l = CloudImmersalLocalizer(token: "t", mapIDs: [1], session: URLSession(configuration: .ephemeral))
    XCTAssertEqual(l.name, "cloud")
}
```

- [ ] **Step 2: run, expect compile failure.**
- [ ] **Step 3: implement.** `ImmersalNative` holds `handles: [Int: Int32]` and `ids: [Int32: Int]` under an `NSLock`; `load` calls `icvLoadMap` on `data.withUnsafeBytes`; `localize` builds `var k: [Float] = [fx, fy, ox, oy]`, `var rot: [Float] = [0,0,0,1]`, `var hs = Array(handles.values)`, calls `icvLocalize(0, &hs, Int32(w), Int32(h), &k, px.baseAddress!, 1, 0, &rot)` inside `frame.pixels.withUnsafeMutableBytes` on a *copy* of the data, and maps `info.handle >= 0` to success. First `localize` sets `icvSetInteger("LocalizationMaxPixels", 960 * 720)`. `isAvailable` is `#if targetEnvironment(simulator) false #else true`. `rawPose` converts `simd_float3x3(q)` to row-major `[Float]`. `NativeImmersalLocalizer.localize` runs `ImmersalNative.shared.localize` in `Task.detached(priority: .userInitiated)` and awaits it. `CloudImmersalLocalizer.localize` calls `ImmersalFrameEncoder.png(from:)` then `ImmersalClient.localize(pngData:...)`, returning an `encode` error when PNG fails (same shape as today).
- [ ] **Step 4: run tests, expect PASS.** Commit.

---

### Task 4: Map cache

**Files:**
- Create: `AISEEBIN/Managers/Immersal/ImmersalMapCache.swift`
- Test: `AISEEBINTests/ImmersalMapCacheTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ImmersalMapCache {
      init(directory: URL = Documents/immersal-maps)
      func url(for id: Int) -> URL                    // <dir>/<id>.bytes
      func contains(_ id: Int) -> Bool
      func data(for id: Int) -> Data?
      func missing(from ids: [Int]) -> [Int]
      func remove(_ id: Int)
      func prune(keeping ids: [Int])
      func fetch(_ ids: [Int], token: String, session: URLSession = .shared,
                 progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws
      static let endpoint = URL(string: "https://api.immersal.com/map")!
  }
  ```

- [ ] **Step 1: failing tests** using a temp directory and a `StubProtocol` copied from `ImmersalClientTests` (make it a shared `TestURLStub.swift` in the test target and switch `ImmersalClientTests` to it):

```swift
func testMissingAndContains() { cache has nothing → missing([1,2]) == [1,2]; write url(for:1) → missing == [2] }
func testFetchWritesTheBody() async throws { stub (200, 2 KB of "x") → fetch([5]) → contains(5), data(for:5).count == 2048 }
func testFetchRejectsImmersalJSONErrorAndWritesNothing() async { stub (200, #"{"error":"auth"}"#) → fetch throws whose description contains "auth"; !contains(5) }
func testPruneKeepsOnlyListedIDs() { write 1, 2, 3; prune(keeping: [2]) → contains(2) only }
```

- [ ] **Step 2: run, expect compile failure.**
- [ ] **Step 3: implement.** `fetch` builds `map?token=&id=` per id; a non-200 status or a body under 1024 bytes that decodes as `{"error": ...}` throws `ImmersalMapCache.Failure(message:)`; writes with `.atomic`; progress = fraction of ids done. `prune` lists `*.bytes` in the directory and removes the ones not in `ids`.
- [ ] **Step 4: run tests, expect PASS.** Commit.

---

### Task 5: Localizer factory

**Files:**
- Create: `AISEEBIN/Managers/Immersal/ImmersalLocalizerFactory.swift`
- Test: `AISEEBINTests/ImmersalLocalizerFactoryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum ImmersalLocalizerFactory {
      struct Choice { let localizer: any ImmersalLocalizer; let reason: String }
      static func make(mapIDs: [Int], token: String, cache: ImmersalMapCache,
                       native: ImmersalNative = .shared, nativeAvailable: Bool = ImmersalNative.isAvailable) -> Choice
  }
  ```

- [ ] **Step 1: failing tests**

```swift
func testCloudWhenNativeUnavailable() { make(mapIDs: [1], ..., nativeAvailable: false) → name "cloud", reason contains "simulator" }
func testCloudWhenAnyMapIsMissing() { cache has 1 not 2 → make([1,2], nativeAvailable: true) → "cloud", reason contains "2 not cached" }
func testCloudAndFileRemovedWhenLoadFails() { cache has 1 (garbage bytes); nativeAvailable: true, stub native load returns -1 → "cloud", reason contains "load failed", !cache.contains(1) }
```

(On the simulator the stub makes every `load` fail, which is what the third test needs; the first two never reach `load`.)

- [ ] **Step 2: run, expect compile failure.**
- [ ] **Step 3: implement.** Order: unavailable → cloud "simulator / plugin unavailable"; `missing = cache.missing(from: mapIDs)` non-empty → cloud "map \(ids) not cached"; unload any native ids not in `mapIDs`; for each id not yet loaded, `native.load(mapID:data:)`; a failure removes the file and returns cloud "map \(id) load failed"; else native. Every return also calls `DiagnosticsLog.write("immersal localizer: \(name) (\(reason)) maps=\(mapIDs)")`.
- [ ] **Step 4: run tests, expect PASS.** Commit.

---

### Task 6: Route both callers through the factory

**Files:**
- Modify: `AISEEBIN/Managers/Immersal/PhoneImmersalLocalizer.swift`
- Modify: `AISEEBIN/Glasses/GlassesPositioning.swift`

**Interfaces:**
- Consumes: `ImmersalLocalizerFactory.make`, `ImmersalFrameEncoder.packedLuma/gray`, `GrayFrame`.
- Produces: `PhoneImmersalLocalizer.localizerName: String`, `GlassesPositioning.localizerName: String`; `GlassesPositioning.Localize` becomes `@Sendable (GrayFrame, CameraIntrinsics) async -> ImmersalLocalizeResult`; `GlassesPositioning.init(pedometer:localize:)` unchanged in shape.

- [ ] **Step 1: PhoneImmersalLocalizer.** In `start`, after the token line: `let choice = ImmersalLocalizerFactory.make(mapIDs: alignment.mapIDs, token: token, cache: ImmersalMapCache()); localizer = choice.localizer; localizerName = choice.localizer.name`. In `consume`, replace the luma copy + PNG with `ImmersalFrameEncoder.packedLuma(from: plane)` (still off-thread via `Task.detached`), and in `localize` call `localizer.localize(frame, intrinsics:)`. Keep the diagnostics sample: write `ImmersalFrameEncoder.png(from: frame)` for the first three attempts and every twentieth, as today. `localizerName` is `private(set) var` observable, default "".
- [ ] **Step 2: GlassesPositioning.** Replace `cloudLocalizer(mapIDs:)` with the factory in `start` (only when `usesDefaultLocalizer`); `consume` calls `ImmersalFrameEncoder.gray(from: image, targetWidth: Self.sentFrameWidth)`; `localizeCopied` takes `GrayFrame?`, keeps the sample PNG write via `png(from:)`, calls `localize(frame, intrinsics)`. Add `private(set) var localizerName = ""`.
- [ ] **Step 3: build for simulator and run the whole test suite.** Expected: all green (existing `GlassesPositioningLogicTests` touch only `FixGate`/`PoseExtrapolator`).
- [ ] **Step 4: commit.**

---

### Task 7: Fill the cache and show the mode

**Files:**
- Modify: `AISEEBIN/ViewModels/NavigationViewModel.swift` (`install`, `startPositioning`, `updateDebug`)
- Modify: `AISEEBIN/Glasses/GlassesView.swift:143` (Localizer row)
- Modify: `AISEEBIN/Views/SettingsView.swift` (cached line + button)

- [ ] **Step 1: NavigationViewModel.** Add `@ObservationIgnored private let immersalCache = ImmersalMapCache()` and `private(set) var immersalCacheState: String?`. Add:

```swift
/// Downloads the map binaries a map's alignment names, so the next start
/// localizes on the phone. Best effort: a failure leaves the cloud path.
private func ensureImmersalMaps(for map: NavigationMap, restart: Bool) async {
    guard let ids = map.immersalAlignment?.mapIDs, !ids.isEmpty else { return }
    let missing = immersalCache.missing(from: ids)
    guard !missing.isEmpty else { immersalCacheState = "on device"; return }
    let token = ImmersalConfig.token
    guard !token.isEmpty else { immersalCacheState = "no token"; return }
    immersalCacheState = "downloading \(missing.count) map\(missing.count == 1 ? "" : "s")"
    do {
        try await immersalCache.fetch(missing, token: token)
        immersalCache.prune(keeping: ids)
        immersalCacheState = "on device"
        DiagnosticsLog.write("immersal maps cached: \(ids)")
        if restart { startPositioning() }
    } catch {
        immersalCacheState = "cloud (\(error.localizedDescription))"
        DiagnosticsLog.write("immersal map fetch failed: \(error.localizedDescription)")
    }
}
```

Call `await ensureImmersalMaps(for: remote.graph, restart: false)` in `install` just before `reloadMapAndRestart()`, and in `startPositioning` for both branches that use Immersal (`phoneAnchoredByImmersal` and `.glasses`): `Task { await ensureImmersalMaps(for: baseMap, restart: true) }` — but only when `immersalCache.missing(from:)` is non-empty, so a cached map never restarts itself. In `updateDebug`, append ` \(phoneLocalizer.localizerName)` / `glassesPositioning.localizerName` to the trackingState strings.

- [ ] **Step 2: GlassesView.** After the Fixes row: `LabeledContent("Localizer", value: positioning.localizerName.isEmpty ? "—" : positioning.localizerName)`.
- [ ] **Step 3: SettingsView.** In `immersalSection`, after the token field: a `LabeledContent("Cached on device", value: cachedText)` where `cachedText` lists the ids from `mapIDsText.immersalMapIDs` that `ImmersalMapCache().contains`, or "none"; and `Button("Download maps for offline use") { Task { try? await ImmersalMapCache().fetch(ids, token: ImmersalConfig.token); refresh } }` disabled when the token is empty.
- [ ] **Step 4: build simulator, run all tests; build device.** Commit.

---

### Task 8: Verify and record

- [ ] Device build (`generic/platform=iOS`) links: `nm` shows `_icvLocalize` as `T` in the app binary.
- [ ] Full simulator test suite green.
- [ ] Update memory `aiseebin-glasses.md` and the TestFlight note: the archive command needs nothing new (fetch runs as a build phase), the library location, and what remains owed on device (airplane-mode fix on the phone in 151670/151683; glasses on cellular off; native-vs-REST pose comparison on a matching frame with the scratchpad harness).
- [ ] Commit; do not bump the build number or upload (the user has not asked for a TestFlight build).
