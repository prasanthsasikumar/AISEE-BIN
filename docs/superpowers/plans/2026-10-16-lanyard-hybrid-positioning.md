# Lanyard + Glasses Hybrid Positioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third positioning mode, "Lanyard + glasses": ARKit on a lanyard-worn phone tracks at 60 Hz while Immersal fixes from the phone camera (full pose) and the glasses camera (position only) anchor the session to the map.

**Architecture:** `PhoneImmersalLocalizer` keeps its anchor and gains a pose history plus `offer(glassesFix:arrivedAt:)`; `ImmersalAnchor` gains a position-only update and `install(fit:)`; a pure `PositionPairBootstrap` solves yaw + translation from position pairs when no full-pose fix has arrived; a new `GlassesFixFeed` turns glasses frames into graph-frame fixes the same way `GlassesPositioning` does, without touching it. `NavigationViewModel` gets a `.lanyard` source with explicit branches at every source check; `.phone` and `.glasses` branches are not edited.

**Tech Stack:** Swift 5 / iOS 17, SwiftUI, ARKit, AVFoundation, Immersal REST + native plugin (existing), XCTest, xcodegen 2.45.

**Spec:** `docs/superpowers/specs/2026-10-16-lanyard-hybrid-positioning-design.md`

## Global Constraints

- **Isolation (the user's rule):** no behaviour change to phone mode, glasses (pocket) mode, authoring, field test, guidance or the beacon. `GlassesPositioning.swift`, `ARNavigationManager.swift`, `GuidanceManager.swift`, `Beacon*.swift` are not modified. Existing test files are only appended to, never edited, and every existing test stays green.
- The glasses' heading is never used for yaw. Only position enters the anchor from the glasses.
- Defaults keep today's behaviour: `positioning.glassesMode` defaults to `pocket`; `glasses.streamLatency` defaults to 0.2 s.
- Bootstrap: 4 pairs over 2 m. Anchor gate: `maxJump` 1.5 m, three in a row believed (existing values, shared counters).
- Pose history: keep 2 s, nearest sample within 0.5 s.
- iOS only.
- New source files are added with `xcodegen generate`; commit `AISEE-BIN.xcodeproj/project.pbxproj` with them.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Build and test commands

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN
xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN \
  -destination 'platform=iOS Simulator,id=19416412-211F-4CB7-B70B-F0CA5345AA27' \
  -only-testing:AISEEBINTests/ImmersalAnchorTests 2>&1 | grep -E 'Test Case .* (passed|failed)|error:|\*\* TEST' | tail -40
```

Replace the class after `-only-testing:AISEEBINTests/`. A full run is the same command without `-only-testing` (about three minutes). Simulator build: `xcodebuild build` with the same project/scheme/destination.

## Review Focus

1. A glasses fix arriving before ARKit has produced any pose (history empty) or after a tracking gap longer than 0.5 s: it must be dropped and reported, never paired with a stale pose. Pinned by `PoseHistoryTests.testEmptyGivesNil` and `testNothingWithinToleranceGivesNil` (Task 3) and the `guard let sessionPose` in `offer`; the localizer itself has no unit harness (ARKit frames).
2. Position fixes and pose fixes disagreeing in alternation: the three-in-a-row rule must count both kinds together, or a wild camera could be believed after two rejections of the other camera. Test in Task 1 (`testPoseFixAfterPositionRejectionsSharesTheCount`).
3. A bootstrap whose pairs span 2 m along one line only: Procrustes still has a unique yaw in 2D from two distinct points, so the fit is valid; what must not happen is a solve from four nearly identical points. Test in Task 2 (`testRefusesOneMetreSpread`).
4. Switching away from lanyard (to phone or pocket, or on glasses disconnect): the feed must stop so no fix reaches the anchor of a mode that is not expecting it. Pinned by the explicit `glassesFeed.stop()` lines in the `.phone` and `.glasses` arms (Task 5) and checked by hand.
5. A user who never picks Lanyard: the auto-switch on glasses connect must still go to pocket mode. Test in Task 5 (`GlassesModeTests.testDefaultIsPocket`, `testPocketMapsToGlassesSource`).

---

### Task 1: Position-only fixes on the anchor

**Files:**
- Modify: `AISEEBIN/Managers/Immersal/ImmersalAnchor.swift`
- Test: `AISEEBINTests/ImmersalAnchorTests.swift` (append only)

**Interfaces:**
- Produces: `ImmersalAnchor.updatePosition(graphPosition: SIMD2<Float>, sessionPose: simd_float4x4) -> Bool` (discardable), `ImmersalAnchor.install(fit: Fit)`.

- [ ] **Step 1: Write the failing tests**

Append inside `final class ImmersalAnchorTests`, before its closing brace:

```swift
    // MARK: - Position-only fixes (the glasses in lanyard mode)

    func testPositionFixWithoutAnchorDoesNothing() {
        var anchor = ImmersalAnchor()
        XCTAssertFalse(anchor.updatePosition(graphPosition: SIMD2(1, 1), sessionPose: pose(x: 0, z: 0, heading: 0)))
        XCTAssertFalse(anchor.isAnchored)
        XCTAssertEqual(anchor.fixes, 0)
    }

    func testPositionFixKeepsYawAndMovesTranslation() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 10, z: 10, heading: .pi / 2), sessionPose: pose(x: 0, z: 0, heading: 0))
        // Walked 2 m forward in the session (-z): predicted graph (12, 10). The glasses say (12.5, 10.3).
        XCTAssertTrue(anchor.updatePosition(graphPosition: SIMD2(12.5, 10.3), sessionPose: pose(x: 0, z: -2, heading: 0)))
        XCTAssertEqual(anchor.fixes, 2)
        XCTAssertEqual(anchor.lastJump, simd_length(SIMD2<Float>(0.5, 0.3)), accuracy: 1e-3)
        assertPlanar(try! XCTUnwrap(anchor.toGraph(pose(x: 0, z: -2, heading: 0))), x: 12.5, z: 10.3, heading: .pi / 2)
        XCTAssertEqual(anchor.fit?.yaw ?? -1, .pi / 2, accuracy: 1e-5)
    }

    func testWildPositionFixIsRejectedUntilThreeAgree() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 0, z: 0, heading: 0), sessionPose: pose(x: 0, z: 0, heading: 0))
        let still = pose(x: 0, z: 0, heading: 0)
        XCTAssertFalse(anchor.updatePosition(graphPosition: SIMD2(8, 0), sessionPose: still))
        XCTAssertFalse(anchor.updatePosition(graphPosition: SIMD2(8, 0), sessionPose: still))
        XCTAssertEqual(anchor.rejected, 2)
        assertPlanar(try! XCTUnwrap(anchor.toGraph(still)), x: 0, z: 0, heading: 0)
        XCTAssertTrue(anchor.updatePosition(graphPosition: SIMD2(8, 0), sessionPose: still))
        assertPlanar(try! XCTUnwrap(anchor.toGraph(still)), x: 8, z: 0, heading: 0)
        XCTAssertEqual(anchor.consecutiveRejections, 0)
    }

    func testPoseFixAfterPositionRejectionsSharesTheCount() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 0, z: 0, heading: 0), sessionPose: pose(x: 0, z: 0, heading: 0))
        let still = pose(x: 0, z: 0, heading: 0)
        XCTAssertFalse(anchor.updatePosition(graphPosition: SIMD2(8, 0), sessionPose: still))
        XCTAssertFalse(anchor.update(graphPose: pose(x: 8, z: 0, heading: 0), sessionPose: still))
        XCTAssertTrue(anchor.updatePosition(graphPosition: SIMD2(8, 0), sessionPose: still),
                      "the third disagreement of either kind is believed")
    }

    func testInstalledFitCountsAsTheFirstFix() {
        var anchor = ImmersalAnchor()
        anchor.install(fit: ImmersalAnchor.Fit(yaw: .pi / 2, tx: 10, ty: 0, tz: 10))
        XCTAssertTrue(anchor.isAnchored)
        XCTAssertEqual(anchor.fixes, 1)
        assertPlanar(try! XCTUnwrap(anchor.toGraph(pose(x: 0, z: -2, heading: 0))), x: 12, z: 10, heading: .pi / 2)
    }
```

- [ ] **Step 2: Run to see them fail**

`-only-testing:AISEEBINTests/ImmersalAnchorTests`. Expected: build errors `has no member 'updatePosition'` / `'install'`.

- [ ] **Step 3: Implement**

In `ImmersalAnchor`, after `update(graphPose:sessionPose:)`:

```swift
    /// A position-only fix: the glasses, whose heading is the head's and not
    /// the phone's. Keeps the yaw and the height, moves the translation so the
    /// session pose lands on `graphPosition`, through the same jump gate and
    /// the same three-in-a-row rule, counted together with pose fixes. Does
    /// nothing without a fit; `PositionPairBootstrap` covers that case.
    @discardableResult
    mutating func updatePosition(graphPosition: SIMD2<Float>, sessionPose: simd_float4x4) -> Bool {
        guard let current = fit else { return false }
        let predicted = NavigationGeometry.planarPosition(of: current.transform * sessionPose)
        lastJump = simd_distance(predicted, graphPosition)
        if lastJump > maxJump {
            consecutiveRejections += 1
            rejected += 1
            if consecutiveRejections < maxRejections { return false }
        }
        let delta = graphPosition - predicted
        fit = Fit(yaw: current.yaw, tx: current.tx + delta.x, ty: current.ty, tz: current.tz + delta.y)
        fixes += 1
        consecutiveRejections = 0
        return true
    }

    /// Adopts a fit solved elsewhere (the position-pair bootstrap) as the first fix.
    mutating func install(fit: Fit) {
        self.fit = fit
        fixes += 1
        consecutiveRejections = 0
        lastJump = 0
    }
```

- [ ] **Step 4: Run to see them pass**

Expected: all `ImmersalAnchorTests` pass (the five existing plus five new).

- [ ] **Step 5: Commit**

```bash
git add AISEEBIN/Managers/Immersal/ImmersalAnchor.swift AISEEBINTests/ImmersalAnchorTests.swift
git commit -m "ImmersalAnchor: position-only fixes and an installable fit

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Position-pair bootstrap

**Files:**
- Modify: `AISEEBIN/Models/ImmersalAlignment.swift` (defaulted parameters on `fit`)
- Create: `AISEEBIN/Managers/Immersal/PositionPairBootstrap.swift`
- Create: `AISEEBINTests/PositionPairBootstrapTests.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes: `ImmersalAnchor.Fit` (Task 1), `ImmersalAlignment.fit`.
- Produces: `struct PositionPairBootstrap { var minimumPairs = 4; var minimumSpread: Float = 2; private(set) var pairs: [Pair]; mutating func add(session: SIMD3<Float>, graph: SIMD3<Float>); mutating func reset(); func solve() -> ImmersalAnchor.Fit? }`; `ImmersalAlignment.fit(pairs:mapIDs:minimumPairs:minimumSpread:)` with defaults equal to the statics.

- [ ] **Step 1: Write the failing tests**

Create `AISEEBINTests/PositionPairBootstrapTests.swift`:

```swift
import XCTest
import simd
@testable import AISEEBIN

/// Before any full-pose fix, glasses fixes (position only) and ARKit positions
/// at the same moments give the session-to-graph yaw and translation.
final class PositionPairBootstrapTests: XCTestCase {

    private let yaw: Float = 0.7

    /// Where a session point lands in the graph under yaw 0.7, t = (5, -3), 1.4 m higher.
    private func graph(_ s: SIMD3<Float>) -> SIMD3<Float> {
        let c = cos(yaw), si = sin(yaw)
        return SIMD3(c * s.x - si * s.z + 5, s.y + 1.4, si * s.x + c * s.z - 3)
    }

    private let walk: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0.1, -0.5), SIMD3(2, 0, -1.5), SIMD3(2.5, -0.1, -2.5)]

    func testRecoversPlantedTransformFromFourPairs() throws {
        var b = PositionPairBootstrap()
        for s in walk { b.add(session: s, graph: graph(s)) }
        let fit = try XCTUnwrap(b.solve())
        XCTAssertEqual(fit.yaw, yaw, accuracy: 1e-4)
        XCTAssertEqual(fit.tx, 5, accuracy: 1e-3)
        XCTAssertEqual(fit.tz, -3, accuracy: 1e-3)
        XCTAssertEqual(fit.ty, 1.4, accuracy: 1e-4)
        // A later session pose maps where the planted transform says.
        let s = SIMD3<Float>(4, 0.2, -3)
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(s.x, s.y, s.z, 1)
        let mapped = (fit.transform * pose).columns.3
        let expected = graph(s)
        XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-3)
        XCTAssertEqual(mapped.z, expected.z, accuracy: 1e-3)
    }

    func testRefusesThreePairs() {
        var b = PositionPairBootstrap()
        for s in walk.prefix(3) { b.add(session: s, graph: graph(s)) }
        XCTAssertNil(b.solve())
    }

    func testRefusesOneMetreSpread() {
        var b = PositionPairBootstrap()
        for s in [SIMD3<Float>(0, 0, 0), SIMD3(0.3, 0, 0), SIMD3(0.6, 0, -0.2), SIMD3(0.9, 0, -0.3)] {
            b.add(session: s, graph: graph(s))
        }
        XCTAssertNil(b.solve())
    }

    func testResetClearsThePairs() {
        var b = PositionPairBootstrap()
        for s in walk { b.add(session: s, graph: graph(s)) }
        b.reset()
        XCTAssertTrue(b.pairs.isEmpty)
        XCTAssertNil(b.solve())
    }
}
```

- [ ] **Step 2: Create the implementation and the defaulted parameters**

In `AISEEBIN/Models/ImmersalAlignment.swift`, change the signature of `fit` to:

```swift
    static func fit(pairs: [Pair], mapIDs: [Int],
                    minimumPairs: Int = ImmersalAlignment.minimumPairs,
                    minimumSpread: Float = ImmersalAlignment.minimumSpread) throws -> ImmersalAlignment {
```

The body's `guard pairs.count >= minimumPairs` and `guard spread >= minimumSpread` now read the parameters, whose defaults are the same statics, so the probe walk is unchanged.

Create `AISEEBIN/Managers/Immersal/PositionPairBootstrap.swift`:

```swift
import Foundation
import simd

/// Anchors the ARKit session from position-only fixes (the glasses in lanyard
/// mode) before any full-pose fix has arrived. Each glasses fix pairs where
/// ARKit says the phone is with where Immersal says the head is; once the
/// pairs span enough ground, the yaw and translation fall out of the same 2D
/// Procrustes fit the probe walk uses. The head-to-chest offset is noise here.
struct PositionPairBootstrap: Equatable {
    var minimumPairs = 4
    var minimumSpread: Float = 2

    struct Pair: Equatable {
        /// ARKit camera position (x, y, z) when the glasses frame was shot.
        var session: SIMD3<Float>
        /// Immersal camera position in the graph frame.
        var graph: SIMD3<Float>
    }

    private(set) var pairs: [Pair] = []

    mutating func add(session: SIMD3<Float>, graph: SIMD3<Float>) {
        pairs.append(Pair(session: session, graph: graph))
    }

    mutating func reset() { pairs.removeAll() }

    /// The fit, or `nil` while too little ground is covered.
    func solve() -> ImmersalAnchor.Fit? {
        let planar = pairs.map {
            ImmersalAlignment.Pair(immersal: SIMD2($0.session.x, $0.session.z), graph: SIMD2($0.graph.x, $0.graph.z))
        }
        guard let a = try? ImmersalAlignment.fit(pairs: planar, mapIDs: [],
                                                 minimumPairs: minimumPairs, minimumSpread: minimumSpread) else { return nil }
        let ty = pairs.reduce(Float(0)) { $0 + ($1.graph.y - $1.session.y) } / Float(pairs.count)
        return ImmersalAnchor.Fit(yaw: a.yaw, tx: a.tx, ty: ty, tz: a.tz)
    }
}
```

- [ ] **Step 3: Add to the project and run**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN && xcodegen generate 2>&1 | tail -1
```

Run `-only-testing:AISEEBINTests/PositionPairBootstrapTests -only-testing:AISEEBINTests/ImmersalAlignmentTests`. Expected: the four new tests pass and all `ImmersalAlignmentTests` pass unchanged (the first run before Step 2 would have failed to build; if you ran it, the error was `cannot find 'PositionPairBootstrap'`).

- [ ] **Step 4: Commit**

```bash
git add AISEEBIN/Models/ImmersalAlignment.swift AISEEBIN/Managers/Immersal/PositionPairBootstrap.swift AISEEBINTests/PositionPairBootstrapTests.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "PositionPairBootstrap: session-to-graph fit from position-only fixes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Pose history and glasses fixes on the phone localizer

**Files:**
- Create: `AISEEBIN/Managers/Immersal/PoseHistory.swift`
- Create: `AISEEBINTests/PoseHistoryTests.swift`
- Modify: `AISEEBIN/Managers/Immersal/PhoneImmersalLocalizer.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes: `ImmersalAnchor.updatePosition/install` (Task 1), `PositionPairBootstrap` (Task 2).
- Produces: `struct PoseHistory { var keep: TimeInterval = 2; var tolerance: TimeInterval = 0.5; mutating func record(_: simd_float4x4, at: TimeInterval); mutating func reset(); func pose(at: TimeInterval) -> simd_float4x4? }`; on `PhoneImmersalLocalizer`: `start(alignment:recordHistory: Bool = false)`, `var streamLatency: TimeInterval`, `private(set) var glassesFixes: Int`, `func offer(glassesFix graphPose: simd_float4x4, arrivedAt: TimeInterval)`.

- [ ] **Step 1: Write the failing tests**

Create `AISEEBINTests/PoseHistoryTests.swift`:

```swift
import XCTest
import simd
@testable import AISEEBIN

/// A glasses fix arrives some 200 ms after its frame was shot; the ARKit pose
/// it pairs with is the one from *then*.
final class PoseHistoryTests: XCTestCase {

    private func pose(x: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3.x = x
        return m
    }

    func testEmptyGivesNil() {
        XCTAssertNil(PoseHistory().pose(at: 1))
    }

    func testNearestSampleWins() {
        var h = PoseHistory()
        h.record(pose(x: 1), at: 10.0)
        h.record(pose(x: 2), at: 10.1)
        h.record(pose(x: 3), at: 10.2)
        XCTAssertEqual(h.pose(at: 10.12)?.columns.3.x, 2)
        XCTAssertEqual(h.pose(at: 10.19)?.columns.3.x, 3)
    }

    func testNothingWithinToleranceGivesNil() {
        var h = PoseHistory()
        h.record(pose(x: 1), at: 10)
        XCTAssertNil(h.pose(at: 10.6))
        XCTAssertNotNil(h.pose(at: 10.4))
    }

    func testKeepsOnlyTheLastTwoSeconds() {
        var h = PoseHistory()
        h.record(pose(x: 1), at: 0)
        h.record(pose(x: 2), at: 1)
        h.record(pose(x: 3), at: 2.5)
        h.record(pose(x: 4), at: 3.1)
        XCTAssertNil(h.pose(at: 1), "dropped: older than 2 s before the newest sample")
        XCTAssertEqual(h.pose(at: 2.5)?.columns.3.x, 3)
    }

    func testResetForgets() {
        var h = PoseHistory()
        h.record(pose(x: 1), at: 10)
        h.reset()
        XCTAssertNil(h.pose(at: 10))
    }
}
```

- [ ] **Step 2: Create `PoseHistory`**

`AISEEBIN/Managers/Immersal/PoseHistory.swift`:

```swift
import Foundation
import simd

/// The last couple of seconds of ARKit poses, so a glasses fix that arrives
/// after its frame was shot can be paired with where the phone was *then*.
struct PoseHistory: Equatable {
    /// How far back samples are kept.
    var keep: TimeInterval = 2
    /// The nearest sample must be this close in time, or there is no answer.
    var tolerance: TimeInterval = 0.5

    struct Sample: Equatable {
        var time: TimeInterval
        var transform: simd_float4x4
    }

    private(set) var samples: [Sample] = []

    mutating func record(_ transform: simd_float4x4, at time: TimeInterval) {
        samples.append(Sample(time: time, transform: transform))
        let cutoff = time - keep
        if let first = samples.firstIndex(where: { $0.time >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
    }

    mutating func reset() { samples.removeAll() }

    /// The sample nearest `time`, or `nil` when none is within `tolerance`.
    func pose(at time: TimeInterval) -> simd_float4x4? {
        guard let best = samples.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(best.time - time) <= tolerance else { return nil }
        return best.transform
    }
}
```

- [ ] **Step 3: Add to the project and run the history tests**

`xcodegen generate`, then `-only-testing:AISEEBINTests/PoseHistoryTests`. Expected: 5 pass.

- [ ] **Step 4: Extend `PhoneImmersalLocalizer`**

All additions; the existing phone-anchored flow is untouched except one `bootstrap.reset()` line on an accepted pose fix and an opt-in history record.

1. New stored state, next to `@ObservationIgnored private let claim = Claim()`:

```swift
    /// Fixes offered by the glasses camera in lanyard mode (position only).
    private(set) var glassesFixes = 0
    /// Glasses frame → phone latency: how far back in the ARKit history a
    /// glasses fix is paired. Persisted; tuned on the Glasses screen.
    var streamLatency: TimeInterval = UserDefaults.standard.object(forKey: "glasses.streamLatency") as? Double ?? 0.2 {
        didSet { UserDefaults.standard.set(streamLatency, forKey: "glasses.streamLatency") }
    }
    @ObservationIgnored private var bootstrap = PositionPairBootstrap()
    @ObservationIgnored private let history = HistoryBox()

    /// ARKit poses, written on ARKit's thread and read on the main actor.
    /// Recording is opt-in (lanyard mode) so phone mode pays nothing.
    private final class HistoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var history = PoseHistory()
        private var enabled = false
        func set(enabled: Bool) { lock.withLock { self.enabled = enabled; if !enabled { history.reset() } } }
        func record(_ t: simd_float4x4, at time: TimeInterval) {
            lock.withLock { if enabled { history.record(t, at: time) } }
        }
        func pose(at time: TimeInterval) -> simd_float4x4? { lock.withLock { history.pose(at: time) } }
    }
```

2. `start(alignment:)` becomes `start(alignment: ImmersalAlignment?, recordHistory: Bool = false)`; after `anchor.reset()` add:

```swift
        bootstrap.reset()
        glassesFixes = 0
        history.set(enabled: recordHistory)
```

3. In `stop()`, after `claim.disarm()`, add `history.set(enabled: false)`.

4. In `consume(_:trackingNormal:)`, as the **first** line of the body (before the claim guard):

```swift
        if trackingNormal { history.record(frame.camera.transform, at: frame.timestamp) }
```

5. In `apply`, inside `if anchor.update(graphPose: graphPose, sessionPose: sessionPose) {`, after `lastError = nil`, add `bootstrap.reset()`.

6. New method after `apply`:

```swift
    /// A glasses fix in lanyard mode: position only, paired with the session
    /// pose from when the frame was shot (arrival minus the stream latency).
    /// With an anchor it nudges the translation; without one it feeds the
    /// bootstrap until that solves.
    func offer(glassesFix graphPose: simd_float4x4, arrivedAt: TimeInterval) {
        guard running else { return }
        guard let sessionPose = history.pose(at: arrivedAt - streamLatency) else {
            lastError = "glasses fix: no ARKit pose for that moment"
            DiagnosticsLog.write("glasses-fix dropped: no session pose within 0.5 s")
            return
        }
        glassesFixes += 1
        let graphPosition = NavigationGeometry.planarPosition(of: graphPose)
        if anchor.isAnchored {
            if anchor.updatePosition(graphPosition: graphPosition, sessionPose: sessionPose) {
                lastError = nil
                lastFixAt = arrivedAt
                DiagnosticsLog.write(String(format: "glasses-fix %d: graph (%.2f, %.2f) jump %.1f m", glassesFixes, graphPosition.x, graphPosition.y, anchor.lastJump))
            } else {
                lastError = String(format: "glasses fix rejected: jumped %.1f m", anchor.lastJump)
                DiagnosticsLog.write(String(format: "glasses-fix rejected: jumped %.1f m", anchor.lastJump))
            }
            return
        }
        let s = sessionPose.columns.3, g = graphPose.columns.3
        bootstrap.add(session: SIMD3(s.x, s.y, s.z), graph: SIMD3(g.x, g.y, g.z))
        DiagnosticsLog.write("glasses-fix bootstrap pair \(bootstrap.pairs.count)")
        guard let fit = bootstrap.solve() else { return }
        anchor.install(fit: fit)
        bootstrap.reset()
        lastError = nil
        lastFixAt = arrivedAt
        DiagnosticsLog.write(String(format: "glasses-fix anchored by bootstrap: yaw %.0f deg t (%.1f, %.1f)", fit.yaw * 180 / .pi, fit.tx, fit.tz))
        onFirstFix?()
    }
```

- [ ] **Step 5: Build and run the phone-side tests**

Simulator `xcodebuild build`, expected `** BUILD SUCCEEDED **`. Then `-only-testing:AISEEBINTests/PoseHistoryTests -only-testing:AISEEBINTests/ImmersalAnchorTests -only-testing:AISEEBINTests/LocalizerReselectionTests`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add AISEEBIN/Managers/Immersal/PoseHistory.swift AISEEBINTests/PoseHistoryTests.swift AISEEBIN/Managers/Immersal/PhoneImmersalLocalizer.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "PhoneImmersalLocalizer: ARKit pose history and position-only glasses fixes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: GlassesFixFeed

**Files:**
- Create: `AISEEBIN/Glasses/GlassesFixFeed.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes: `GlassesPositioning.minimumInterval` / `.sentFrameWidth` (nonisolated statics, read only), `GlassesCamera`, `ImmersalFrameEncoder.copyBGRA/gray`, `ImmersalLocalizerFactory.select`, `ImmersalPose.cameraPoseInMap`, `ImmersalAlignment.toGraph`, `ImmersalConfig`.
- Produces: `@MainActor @Observable final class GlassesFixFeed` with `start(alignment:)`, `stop()`, `reselectLocalizer()`, `nonisolated consume(_ frame: AiSeeFrame)`, `onFix: ((simd_float4x4, TimeInterval) -> Void)?`, counters `attempts`, `fixes`, `lastError`, `lastLatencyMS`, `lastMapID`, `localizerName`, `running`.

No unit test: it is the network/plugin pipeline, verified like `GlassesPositioning` is, by hand (Task 6). Its logic is a copy of the proven `GlassesPositioning.consume` → `localizeCopied` → pose decode, minus the pedometer and the extrapolator.

- [ ] **Step 1: Create the file**

```swift
import Foundation
import Observation
import OSLog
import simd

/// The glasses camera as a source of Immersal fixes for lanyard mode. A frame
/// goes to the localizer the way `GlassesPositioning` sends it (same cadence,
/// width and lens model) and a fix comes back as a camera pose in the graph
/// frame, with the time the frame arrived. No pedometer, no extrapolation, no
/// snapshots: ARKit on the phone is the tracker, and
/// `PhoneImmersalLocalizer.offer` folds each fix into its anchor.
@MainActor
@Observable
final class GlassesFixFeed {
    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "glasses-fix")

    private(set) var attempts = 0
    private(set) var fixes = 0
    private(set) var lastError: String?
    private(set) var lastLatencyMS: Int?
    private(set) var lastMapID: Int?
    /// "on device" or "cloud" for this session.
    private(set) var localizerName = ""
    private(set) var running = false

    /// A fix: camera pose in the graph frame, and when the frame arrived
    /// (`ProcessInfo.systemUptime`, the same clock as ARKit's frame timestamps).
    @ObservationIgnored var onFix: ((simd_float4x4, TimeInterval) -> Void)?

    var camera = GlassesCamera.load()

    @ObservationIgnored private var alignment: ImmersalAlignment?
    @ObservationIgnored private var localizer: (any ImmersalLocalizer)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let claim = FrameClaim()

    /// Touched on the SDK thread: whether a frame may be claimed right now.
    private final class FrameClaim: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        private var lastClaimAt: TimeInterval = -.infinity
        private var generation = 0

        func arm(generation: Int) {
            lock.withLock { self.generation = generation; claimed = false; lastClaimAt = -.infinity }
        }
        func disarm() { lock.withLock { generation = 0; claimed = false } }
        func tryClaim(now: TimeInterval, minimumInterval: TimeInterval) -> Int? {
            lock.withLock {
                guard generation > 0, !claimed, now - lastClaimAt >= minimumInterval else { return nil }
                claimed = true
                lastClaimAt = now
                return generation
            }
        }
        func release() { lock.withLock { claimed = false } }
    }

    func start(alignment: ImmersalAlignment?) {
        stop()
        self.alignment = alignment
        generation += 1
        attempts = 0; fixes = 0
        lastError = nil; lastLatencyMS = nil; lastMapID = nil
        guard let alignment else {
            lastError = "Map not aligned"
            return
        }
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        guard !ImmersalConfig.token.isEmpty, !mapIDs.isEmpty else {
            lastError = ImmersalConfig.token.isEmpty ? "No Immersal token" : "No Immersal map ids"
            return
        }
        camera = GlassesCamera.load()
        running = true
        claim.arm(generation: generation)
        DiagnosticsLog.write("glasses-fix start maps=\(mapIDs)")
        reselectLocalizer()
    }

    func stop() {
        guard running else { return }
        running = false
        claim.disarm()
        DiagnosticsLog.write("glasses-fix stop attempts=\(attempts) fixes=\(fixes)")
    }

    /// On-device or cloud for the running session, as the other localizers
    /// choose it; called at start and again when a map binary lands.
    func reselectLocalizer() {
        guard running, let alignment else { return }
        let generation = self.generation
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        let token = ImmersalConfig.token
        Task { [weak self] in
            let choice = await ImmersalLocalizerFactory.select(mapIDs: mapIDs, token: token, cache: ImmersalMapCache())
            guard let self, self.running, generation == self.generation else { return }
            self.localizer = choice.localizer
            self.localizerName = choice.localizer.name
        }
    }

    /// SDK decode thread. The same shape as `GlassesPositioning.consume`.
    nonisolated func consume(_ frame: AiSeeFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let generation = claim.tryClaim(now: now, minimumInterval: GlassesPositioning.minimumInterval) else { return }
        guard let buffer = frame.pixelBuffer,
              let image = ImmersalFrameEncoder.copyBGRA(from: buffer) else {
            claim.release()
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let gray = ImmersalFrameEncoder.gray(from: image, targetWidth: GlassesPositioning.sentFrameWidth)
            await self.localize(gray, arrivedAt: now, generation: generation)
        }
    }

    private func localize(_ frame: GrayFrame?, arrivedAt: TimeInterval, generation: Int) async {
        defer { claim.release() }
        guard running, generation == self.generation, let alignment, let localizer else { return }
        guard let frame else {
            lastError = "encode"
            return
        }
        let intrinsics = camera.intrinsics(width: frame.width, height: frame.height)
        let result = await localizer.localize(frame, intrinsics: intrinsics)
        guard running, generation == self.generation else { return }
        attempts += 1
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastMapID = result.mapID
        Self.logger.notice("localize \(self.attempts): \(result.success ? "fix" : result.error, privacy: .public) map=\(result.mapID ?? -1) \(self.lastLatencyMS ?? 0) ms")
        DiagnosticsLog.write("glasses-fix localize \(attempts): \(result.success ? "fix" : result.error) map=\(result.mapID ?? -1) \(lastLatencyMS ?? 0) ms \(result.requestBytes) B")
        guard result.success, let raw = result.pose, let poseInMap = ImmersalPose.cameraPoseInMap(raw) else {
            lastError = result.success ? "malformed pose" : result.error
            if ImmersalConfig.recoverFromRejectedToken(ImmersalConfig.token, error: result.error) {
                lastError = "\(result.error) · typed token dropped, retrying with the built-in one"
            }
            return
        }
        fixes += 1
        lastError = nil
        onFix?(alignment.toGraph(cameraPose: poseInMap, mapID: result.mapID), arrivedAt)
    }
}
```

- [ ] **Step 2: Add to the project and build**

`xcodegen generate`, then the simulator `xcodebuild build`. Expected: `** BUILD SUCCEEDED **` with no errors in `GlassesFixFeed.swift`. If `copyBGRA`'s return type is not `Sendable` for the detached task, mirror exactly how `GlassesPositioning.consume` captures it (same call, same closure shape) rather than inventing a workaround.

- [ ] **Step 3: Commit**

```bash
git add AISEEBIN/Glasses/GlassesFixFeed.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "GlassesFixFeed: glasses frames to graph-frame fixes for lanyard mode

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The lanyard source, the remembered glasses mode, wiring and the picker

**Files:**
- Create: `AISEEBIN/Glasses/GlassesMode.swift`
- Create: `AISEEBINTests/GlassesModeTests.swift`
- Modify: `AISEEBIN/ViewModels/NavigationViewModel.swift`
- Modify: `AISEEBIN/Glasses/GlassesView.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes: `GlassesFixFeed` (Task 4), `PhoneImmersalLocalizer.start(alignment:recordHistory:)`, `.offer`, `.streamLatency`, `.glassesFixes` (Task 3).
- Produces: `PositioningSource.lanyard`; `enum GlassesMode: String, CaseIterable { case pocket, lanyard }` with `static func load(from:) -> GlassesMode`, `func save(to:)`, `var source: PositioningSource`, `init?(source:)`, `var label: String`; `NavigationViewModel.glassesFeed`.

- [ ] **Step 1: Write the failing tests**

Create `AISEEBINTests/GlassesModeTests.swift`:

```swift
import XCTest
@testable import AISEEBIN

/// Which way the glasses are used once they connect. The default must stay
/// "phone in a pocket": nobody who never picks Lanyard sees a change.
final class GlassesModeTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "GlassesModeTests")
        defaults.removePersistentDomain(forName: "GlassesModeTests")
    }

    func testDefaultIsPocket() {
        XCTAssertEqual(GlassesMode.load(from: defaults), .pocket)
    }

    func testRoundTripsLanyard() {
        GlassesMode.lanyard.save(to: defaults)
        XCTAssertEqual(GlassesMode.load(from: defaults), .lanyard)
    }

    func testGarbageFallsBackToPocket() {
        defaults.set("hat", forKey: GlassesMode.key)
        XCTAssertEqual(GlassesMode.load(from: defaults), .pocket)
    }

    func testPocketMapsToGlassesSource() {
        XCTAssertEqual(GlassesMode.pocket.source, .glasses)
        XCTAssertEqual(GlassesMode.lanyard.source, .lanyard)
    }

    func testSourceRoundTrip() {
        XCTAssertEqual(GlassesMode(source: .glasses), .pocket)
        XCTAssertEqual(GlassesMode(source: .lanyard), .lanyard)
        XCTAssertNil(GlassesMode(source: .phone))
    }
}
```

- [ ] **Step 2: Create `GlassesMode` and the enum case**

`AISEEBIN/Glasses/GlassesMode.swift`:

```swift
import Foundation

/// How the glasses are used once they connect: the phone in a pocket (the
/// glasses position alone, with the pedometer and gyro between fixes) or on a
/// lanyard (ARKit on the phone tracks; both cameras send fixes). Remembered,
/// so the auto-switch on connect goes to the mode the user chose last.
enum GlassesMode: String, CaseIterable {
    case pocket, lanyard

    static let key = "positioning.glassesMode"

    static func load(from defaults: UserDefaults = .standard) -> GlassesMode {
        defaults.string(forKey: key).flatMap(GlassesMode.init(rawValue:)) ?? .pocket
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    var source: PositioningSource {
        self == .pocket ? .glasses : .lanyard
    }

    init?(source: PositioningSource) {
        switch source {
        case .glasses: self = .pocket
        case .lanyard: self = .lanyard
        case .phone: return nil
        }
    }

    var label: String {
        self == .pocket ? "Glasses, phone in pocket" : "Lanyard + glasses"
    }
}
```

In `NavigationViewModel.swift`, `PositioningSource` becomes:

```swift
enum PositioningSource: Hashable {
    /// ARKit on the chest-mounted phone, relocalized into the saved world map.
    case phone
    /// Immersal fixes on the AiSee glasses' video, the phone in a pocket.
    case glasses
    /// ARKit on a lanyard-worn phone tracks; Immersal fixes from the phone
    /// camera (full pose) and the glasses (position only) anchor it.
    case lanyard
}
```

- [ ] **Step 3: Wire the view model**

Each item is one edit. The `.phone` and `.glasses` arms only gain a `glassesFeed.stop()` line.

1. Property, after `let glassesPositioning: GlassesPositioning`:
```swift
    /// Lanyard mode: the glasses camera as a second source of fixes.
    let glassesFeed = GlassesFixFeed()
```

2. `localizationStatus`: change the line `if phoneAnchoredByImmersal, !phoneLocalizer.isAnchored,` to
```swift
        if phoneAnchoredByImmersal || positioningSource == .lanyard, !phoneLocalizer.isAnchored,
```

3. `currentTransform`: change `if phoneAnchoredByImmersal { return phoneLocalizer.toGraph(arManager.cameraTransform) ?? matrix_identity_float4x4 }` to
```swift
        if phoneAnchoredByImmersal || positioningSource == .lanyard {
            return phoneLocalizer.toGraph(arManager.cameraTransform) ?? matrix_identity_float4x4
        }
```

4. `phoneImmersalSummary`: change its guard to
```swift
        guard positioningSource == .lanyard || (positioningSource == .phone && phoneAnchoredByImmersal) else { return nil }
```

5. `startSession`: replace the `glasses.onFrame = …` line with
```swift
        glasses.onFrame = { [weak positioning = glassesPositioning, weak feed = glassesFeed] frame in
            positioning?.consume(frame)   // pocket mode
            feed?.consume(frame)          // lanyard mode; a feed that is not running drops it at the claim
        }
        glassesFeed.onFix = { [weak self] pose, arrivedAt in
            self?.phoneLocalizer.offer(glassesFix: pose, arrivedAt: arrivedAt)
        }
```

6. `startPositioning`: in `case .phone:` add `glassesFeed.stop()` right after `glassesPositioning.stop()`; in `case .glasses:` add `glassesFeed.stop()` right after `phoneLocalizer.stop()`; then add the new arm before the closing brace of the switch:
```swift
        case .lanyard:
            guard let alignment = baseMap.immersalAlignment, !ImmersalConfig.mapIDs(for: alignment).isEmpty else {
                guidance.speak("This map has no Immersal map. Using the phone camera.", interrupt: true)
                Task { @MainActor [weak self] in self?.positioningSource = .phone }
                return
            }
            glassesPositioning.stop()
            DiagnosticsLog.write("startPositioning lanyard map=\(baseMap.name) alignment=\(alignment.mapIDs) latency=\(phoneLocalizer.streamLatency)")
            startARKit(relocalize: false)
            phoneLocalizer.start(alignment: alignment, recordHistory: true)
            glassesFeed.start(alignment: alignment)
            glasses.keepStreaming = true
            fetchImmersalMapsIfMissing(restart: true)
            Task { [glasses, guidance] in
                do {
                    try await glasses.startStreaming()
                } catch {
                    guidance.speak("The glasses camera did not start. \(error.localizedDescription)", interrupt: true)
                }
            }
            guidance.speak("Using the phone and the glasses. Please look around slowly.", interrupt: true)
```

7. `observeGlassesConnection`: replace the two `if` branches with
```swift
                if self.glasses.isConnected, self.positioningSource == .phone {
                    self.positioningSource = GlassesMode.load().source
                } else if !self.glasses.isConnected, self.positioningSource != .phone {
                    self.guidance.speak("Glasses disconnected. Using the phone camera.", interrupt: true)
                    self.positioningSource = .phone
                }
```
and update its doc comment's first sentence to: `/// Follows the glasses: connected means they are on the visitor's face, so the remembered glasses mode (pocket or lanyard) takes over; disconnected hands it back.`

8. `didChange(positioningSource:)`: add as the first line `if let mode = GlassesMode(source: source) { mode.save() }`.

9. `reselectImmersalLocalizer` and the `switch source` inside `fetchImmersalMapsIfMissing`: add to each
```swift
        case .lanyard: phoneLocalizer.reselectLocalizer(); glassesFeed.reselectLocalizer()
```
(in the second one with `self.` prefixes).

10. `fieldMode`: 
```swift
    var fieldMode: String {
        switch positioningSource {
        case .glasses: return "glasses"
        case .lanyard: return "lanyard"
        case .phone: return "phone"
        }
    }
```

11. `reloadMapKeepingSession`: after the existing `if positioningSource == .glasses { … }` add
```swift
        if positioningSource == .lanyard {
            phoneLocalizer.start(alignment: baseMap.immersalAlignment, recordHistory: true)
            glassesFeed.start(alignment: baseMap.immersalAlignment)
        }
```

12. `resetSession`: change `if positioningSource == .glasses || phoneAnchoredByImmersal {` to `if positioningSource != .phone || phoneAnchoredByImmersal {`.

13. `toggleListening`: change `if positioningSource == .glasses, glasses.isConnected {` to `if positioningSource != .phone, glasses.isConnected {`.

14. `anchored(_:)`: change its guard to
```swift
        guard positioningSource == .lanyard || (positioningSource == .phone && phoneAnchoredByImmersal) else { return snapshot }
```

15. `updateDebug`: in the `else` branch, replace the two `phoneAnchoredByImmersal ?` expressions:
```swift
            let viaImmersal = phoneAnchoredByImmersal || positioningSource == .lanyard
            debug.trackingState = viaImmersal
                ? "\(arManager.trackingStateDescription) · immersal \(phoneLocalizer.localizerName) \(phoneLocalizer.fixes)/\(phoneLocalizer.attempts)"
                  + (positioningSource == .lanyard ? " · glasses \(glassesFeed.fixes)/\(glassesFeed.attempts)" : "")
                : arManager.trackingStateDescription
            debug.featurePoints = snapshot.featurePointCount
            debug.worldMapping = viaImmersal ? (phoneLocalizer.lastError ?? "anchored") : arManager.worldMappingStatus.label
```

- [ ] **Step 4: The picker and lanyard status in `GlassesView`**

Add `private var feed: GlassesFixFeed { viewModel.glassesFeed }` next to `positioning`. In `positioningSection`, replace the `Toggle("Use glasses for positioning", …)` (its three lines, through `.disabled(!glasses.isConnected)`) with:

```swift
            Picker("Positioning", selection: Binding(get: { viewModel.positioningSource },
                                                     set: { viewModel.positioningSource = $0 })) {
                Text("Phone").tag(PositioningSource.phone)
                Text(GlassesMode.pocket.label).tag(PositioningSource.glasses)
                Text(GlassesMode.lanyard.label).tag(PositioningSource.lanyard)
            }
            .disabled(!glasses.isConnected)
            if viewModel.positioningSource == .lanyard {
                LabeledContent("Anchored", value: viewModel.phoneLocalizer.isAnchored ? "yes" : "not yet")
                LabeledContent("Anchor fixes", value: "\(viewModel.phoneLocalizer.fixes) / \(viewModel.phoneLocalizer.attempts) phone tries")
                LabeledContent("Glasses fixes", value: "\(feed.fixes) / \(feed.attempts)")
                LabeledContent("Glasses localizer", value: feed.localizerName.isEmpty ? "—" : feed.localizerName)
                Stepper(value: Binding(get: { viewModel.phoneLocalizer.streamLatency },
                                       set: { viewModel.phoneLocalizer.streamLatency = $0 }),
                        in: 0...1, step: 0.05) {
                    LabeledContent("Stream latency", value: String(format: "%.2f s", viewModel.phoneLocalizer.streamLatency))
                }
                if let error = feed.lastError ?? viewModel.phoneLocalizer.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
```

In the section footer, replace the `else { Text("The phone camera is paused …") }` branch with:
```swift
            } else if viewModel.positioningSource == .lanyard {
                Text("The phone hangs on a lanyard, camera forward: ARKit tracks, and both cameras send fixes. The glasses' heading is not used, only where they are.")
            } else {
                Text("The phone camera is paused while the glasses position you. Switch back to hand the phone to a helper.")
            }
```

- [ ] **Step 5: Add files, build, run the full suite**

`xcodegen generate`; simulator `xcodebuild build` → `** BUILD SUCCEEDED **`; then the full test run (no `-only-testing`). Expected: every class green, including the new `GlassesModeTests` (5) and all previously existing classes unchanged.

- [ ] **Step 6: Commit**

```bash
git add AISEEBIN/Glasses/GlassesMode.swift AISEEBINTests/GlassesModeTests.swift AISEEBIN/ViewModels/NavigationViewModel.swift AISEEBIN/Glasses/GlassesView.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "Lanyard + glasses positioning: ARKit tracks, both cameras anchor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: README, device build, hand checks

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

In the Glasses part of `README.md` (search for "Use glasses for positioning" or "glasses" in the hands-free/field sections), add:

`**Lanyard + glasses** (Glasses screen → Positioning): wear the phone on a lanyard with the camera facing forward and the glasses on. ARKit on the phone tracks at 60 Hz; Immersal fixes from both cameras anchor it to the map (the glasses contribute position only). The choice is remembered and used the next time the glasses connect. Needs a map with an Immersal alignment.`

Commit:
```bash
git add README.md
git commit -m "README: lanyard + glasses positioning

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 2: Device build and install**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN
xcodebuild build -project AISEE-BIN.xcodeproj -scheme AISEEBIN -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_F26W9MD3G9.p8" \
  -authenticationKeyID F26W9MD3G9 -authenticationKeyIssuerID 57b4dae3-2c6d-4cac-ae62-4ad91443fb4b \
  IMMERSAL_DEFAULT_TOKEN="$(cat "$HOME/.config/aiseebin/immersal_pro_token")" 2>&1 | grep -E 'error:|\*\* BUILD' | tail -3
xcrun devicectl device install app --device 00008150-001410210C7A401C build/dd/Build/Products/Debug-iphoneos/AISEEBIN.app 2>&1 | grep -E -i 'installed|error'
```

- [ ] **Step 3: Hand checks (the user, on site, with a map that has an Immersal alignment)**

1. Glasses screen → Positioning → Lanyard + glasses. Spoken: "Using the phone and the glasses…". The phone camera preview keeps running (ARKit not paused).
2. Cover the phone camera with a hand and walk 3 m: "Anchored" turns to yes from glasses fixes alone (bootstrap); the live map follows.
3. Uncover: phone fixes appear; "Anchor fixes" grows from both.
4. Turn the head left and right while walking straight: the live-map heading does not swing (yaw is the chest's).
5. Take the glasses off / power them down: "Glasses disconnected. Using the phone camera." and phone mode.
6. Reconnect the glasses: it returns to Lanyard (remembered), not pocket.
7. Pocket-mode regression: pick "Glasses, phone in pocket": exactly today's behaviour, phone camera paused, pedometer status rows shown.
8. Pull `immersal-diag.log` and check for `glasses-fix` lines, `glasses-fix anchored by bootstrap` when the phone camera was covered, and no `glasses-fix dropped: no session pose` streak longer than ARKit's gaps.
