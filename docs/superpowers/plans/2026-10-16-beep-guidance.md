# Beep Guidance (Heading Beacon) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional, off-by-default beep that tells a blind walker whether they are heading along the route, reacting to turns at once on the phone and on the glasses.

**Architecture:** A pure `BeaconPolicy` turns the bearing to a look-ahead point on the route into one of three cues (silent, on course, off course left/right); `BeaconSynth` plays looping synthesized patterns for the cue through the existing audio session. In glasses mode a gyro integrator (`TurnIntegrator`, fed by `CMDeviceMotion`) gives the turn since the last Immersal fix, so `PoseExtrapolator` reports a live heading between fixes. `NavigationViewModel` wires the three together in its per-snapshot loop.

**Tech Stack:** Swift 5 / iOS 17, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`), CoreMotion (`CMMotionManager`), XCTest, xcodegen 2.45.

**Spec:** `docs/superpowers/specs/2026-10-16-beep-guidance-design.md`

## Global Constraints

- iOS only. Android is out of scope (it has no route guidance).
- Off by default: `UserDefaults` key `guidance.beacon`, `false` unless set.
- Silence always means "position not trusted"; never play a cue when `trackingReliable` is false or no route is active.
- Hysteresis: off course beyond 25°, on course within 15°. Look-ahead 3 m. Pan reaches ±1 at 90°.
- Sounds: on course = one 60 ms tick at 880 Hz every 0.6 s, centred. Off course = 440 Hz every 1.2 s: left = two quick ticks, right = one long (300 ms) tone, panned to that side. Boundary = three descending notes once.
- With the beacon on, the progress reminder interval is 30 s (default 12 s).
- Heading sign: clockwise-positive, a right turn increases heading (`NavigationGeometry.heading`), matching `relativeBearing` where positive = turn right.
- New source files must be added to the Xcode project with `xcodegen generate` and the regenerated `AISEE-BIN.xcodeproj/project.pbxproj` committed with them.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Build and test commands

Unit tests (simulator, one class at a time keeps a run under two minutes):

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN
xcodebuild test -project AISEE-BIN.xcodeproj -scheme AISEEBIN \
  -destination 'platform=iOS Simulator,id=19416412-211F-4CB7-B70B-F0CA5345AA27' \
  -only-testing:AISEEBINTests/RouteTrackerTests 2>&1 | grep -E 'Test Case .* (passed|failed)|error:|\*\* TEST' | tail -40
```

Replace the class after `-only-testing:AISEEBINTests/` per task. A full run is the same command without `-only-testing`.

Type-check the app without a full build (fast, catches most mistakes):

```bash
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
$TC/swiftc -typecheck -module-name AISEEBIN -sdk $SDK -target arm64-apple-ios17.0-simulator \
  -swift-version 5 -strict-concurrency=targeted $(find AISEEBIN -name "*.swift")
```

If any Apple shim answers "You have not agreed to the Xcode license agreements", the user must run `! sudo xcodebuild -license accept`.

## Review Focus

1. A route whose remaining length is shorter than the look-ahead (last 3 m before arrival): the aim point must be the destination, never a point past it. Test in Task 1.
2. A bearing near ±180° (walker facing away): side must be chosen by sign and pan clamped to ±1; the cue must not flip side each frame around exactly ±180°. Test in Task 2 (pan clamp, and ±179.9° keep their sign).
3. Device motion timestamps that repeat or go backwards (CoreMotion can deliver duplicates after an interruption): the integrator must ignore them, not add a negative or huge step. Test in Task 3.
4. The gyro source restarting (positioning stopped and started): the turn counter resets, and a fix anchored before the reset would produce a wrong offset; `GlassesPositioning.start` resets the extrapolator before the source starts, so no fix survives a restart. Test in Task 4 (anchor, reset, anchor again gives offset 0).
5. "stop" spoken while the beacon is on ("stop", not "stop beeps") must still stop navigation; only transcripts that mention beeps or the beacon are beacon commands. Test in Task 5.

---

### Task 1: Look-ahead aim point on the route

**Files:**
- Modify: `AISEEBIN/Managers/RouteTracker.swift` (add a method after `remainingDistance`)
- Test: `AISEEBINTests/RouteTrackerTests.swift`

**Interfaces:**
- Consumes: `RouteTracker.path`, `targetIndex`, `targetNode`, `previousNode` (existing).
- Produces: `func aimPoint(from position: SIMD2<Float>, lookAhead: Float) -> SIMD2<Float>?` — `nil` once arrived.

- [ ] **Step 1: Write the failing tests**

Append to `final class RouteTrackerTests` in `AISEEBINTests/RouteTrackerTests.swift`, before its closing brace. The sample map: entrance (0,0) → junction (0,−8) → tropical (−6,−8) → orchid (−6,−14); entrance → restrooms (6,−2) is a single edge.

```swift
    // MARK: - Aim point

    func testAimPointLiesLookAheadMetresAlongStraightLeg() {
        let t = tracker("entrance", "orchid")                 // leg (0,0) -> (0,-8)
        let aim = t.aimPoint(from: SIMD2<Float>(0.5, -2), lookAhead: 3)!
        XCTAssertEqual(aim.x, 0, accuracy: 1e-5)               // projected onto the leg
        XCTAssertEqual(aim.y, -5, accuracy: 1e-5)              // 3 m past the projection (0,-2)
    }

    func testAimPointCrossesIntoNextLeg() {
        let t = tracker("entrance", "orchid")
        // 1 m before the junction; 2 m of look-ahead continue toward tropical (-6,-8).
        let aim = t.aimPoint(from: SIMD2<Float>(0, -7), lookAhead: 3)!
        XCTAssertEqual(aim.x, -2, accuracy: 1e-5)
        XCTAssertEqual(aim.y, -8, accuracy: 1e-5)
    }

    func testAimPointStopsAtDestinationWhenRouteIsShorter() {
        let t = tracker("entrance", "restrooms")              // single leg to (6,-2)
        let aim = t.aimPoint(from: SIMD2<Float>(0, 0), lookAhead: 100)!
        XCTAssertEqual(aim.x, 6, accuracy: 1e-5)
        XCTAssertEqual(aim.y, -2, accuracy: 1e-5)
    }

    func testAimPointProjectsPositionBehindLegStartOntoStart() {
        let t = tracker("entrance", "orchid")
        let aim = t.aimPoint(from: SIMD2<Float>(0, 3), lookAhead: 3)!   // behind the entrance
        XCTAssertEqual(aim.x, 0, accuracy: 1e-5)
        XCTAssertEqual(aim.y, -3, accuracy: 1e-5)
    }

    func testAimPointIsNilOnceArrived() {
        let t = tracker("orchid", "orchid")
        XCTAssertNil(t.aimPoint(from: .zero, lookAhead: 3))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command with `-only-testing:AISEEBINTests/RouteTrackerTests`.
Expected: build error `value of type 'RouteTracker' has no member 'aimPoint'`.

- [ ] **Step 3: Implement `aimPoint`**

Add to `struct RouteTracker` in `AISEEBIN/Managers/RouteTracker.swift`, after `remainingDistance`:

```swift
    /// A point `lookAhead` metres further along the route than the user's
    /// projection onto the current leg, or the destination when the route
    /// ends sooner. A beacon aimed here steers along the path instead of
    /// swinging toward each node as it is passed. `nil` once arrived.
    func aimPoint(from position: SIMD2<Float>, lookAhead: Float) -> SIMD2<Float>? {
        guard let target = targetNode else { return nil }
        let from = previousNode?.position ?? target.position
        let leg = target.position - from
        let lengthSquared = simd_length_squared(leg)
        let t: Float = lengthSquared > .ulpOfOne ? simd_clamp(simd_dot(position - from, leg) / lengthSquared, 0, 1) : 1
        var point = from + leg * t
        var remaining = lookAhead
        var index = targetIndex
        var next = target.position
        while true {
            let step = simd_distance(point, next)
            if step >= remaining {
                guard step > .ulpOfOne else { return next }
                return point + (next - point) * (remaining / step)
            }
            remaining -= step
            point = next
            index += 1
            guard index < path.count else { return next }   // ran out of route: the destination
            next = path[index].position
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command. Expected: all `RouteTrackerTests` pass, including the five new ones.

- [ ] **Step 5: Commit**

```bash
git add AISEEBIN/Managers/RouteTracker.swift AISEEBINTests/RouteTrackerTests.swift
git commit -m "RouteTracker: look-ahead aim point along the route

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: BeaconPolicy

**Files:**
- Create: `AISEEBIN/Managers/BeaconPolicy.swift`
- Create: `AISEEBINTests/BeaconPolicyTests.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Produces:
  - `enum BeaconSide: Equatable { case left, right }`
  - `enum BeaconCue: Equatable { case silent; case onCourse; case offCourse(side: BeaconSide, pan: Float) }`
  - `struct BeaconPolicy` with `mutating func evaluate(bearing: Float?, trackingReliable: Bool, navigating: Bool) -> BeaconCue`, `mutating func reset()`, `private(set) var isOffCourse: Bool`.

- [ ] **Step 1: Write the failing tests**

Create `AISEEBINTests/BeaconPolicyTests.swift`:

```swift
import XCTest
@testable import AISEEBIN

final class BeaconPolicyTests: XCTestCase {

    private var policy = BeaconPolicy()
    private func deg(_ d: Float) -> Float { d * .pi / 180 }

    func testSilentWhenNotNavigating() {
        XCTAssertEqual(policy.evaluate(bearing: 0, trackingReliable: true, navigating: false), .silent)
    }

    func testSilentWhenTrackingUnreliable() {
        XCTAssertEqual(policy.evaluate(bearing: 0, trackingReliable: false, navigating: true), .silent)
    }

    func testSilentWithoutBearing() {
        XCTAssertEqual(policy.evaluate(bearing: nil, trackingReliable: true, navigating: true), .silent)
    }

    func testOnCourseInsideFifteenDegrees() {
        XCTAssertEqual(policy.evaluate(bearing: deg(10), trackingReliable: true, navigating: true), .onCourse)
        XCTAssertEqual(policy.evaluate(bearing: deg(-14), trackingReliable: true, navigating: true), .onCourse)
    }

    func testOffCourseRightBeyondTwentyFiveDegrees() {
        let cue = policy.evaluate(bearing: deg(30), trackingReliable: true, navigating: true)
        guard case .offCourse(let side, let pan) = cue else { return XCTFail("expected off course, got \(cue)") }
        XCTAssertEqual(side, .right)
        XCTAssertEqual(pan, 30 / 90, accuracy: 1e-5)
    }

    func testOffCourseLeftIsNegativeBearing() {
        let cue = policy.evaluate(bearing: deg(-45), trackingReliable: true, navigating: true)
        guard case .offCourse(let side, let pan) = cue else { return XCTFail("expected off course, got \(cue)") }
        XCTAssertEqual(side, .left)
        XCTAssertEqual(pan, -0.5, accuracy: 1e-5)
    }

    func testHysteresisKeepsStateBetweenFifteenAndTwentyFive() {
        // Still on course at 20° when coming from on course…
        XCTAssertEqual(policy.evaluate(bearing: deg(20), trackingReliable: true, navigating: true), .onCourse)
        // …off course once past 25°…
        _ = policy.evaluate(bearing: deg(30), trackingReliable: true, navigating: true)
        XCTAssertTrue(policy.isOffCourse)
        // …still off course back at 20°…
        if case .onCourse = policy.evaluate(bearing: deg(20), trackingReliable: true, navigating: true) {
            XCTFail("20° must stay off course after being off course")
        }
        // …and on course again within 15°.
        XCTAssertEqual(policy.evaluate(bearing: deg(10), trackingReliable: true, navigating: true), .onCourse)
    }

    func testPanClampsAtNinetyDegrees() {
        guard case .offCourse(_, let right) = policy.evaluate(bearing: deg(150), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(right, 1)
        guard case .offCourse(let side, let left) = policy.evaluate(bearing: deg(-179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(left, -1)
        XCTAssertEqual(side, .left)
        guard case .offCourse(let side2, _) = policy.evaluate(bearing: deg(179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(side2, .right)
    }

    func testResetClearsOffCourse() {
        _ = policy.evaluate(bearing: deg(60), trackingReliable: true, navigating: true)
        policy.reset()
        XCTAssertFalse(policy.isOffCourse)
        XCTAssertEqual(policy.evaluate(bearing: deg(20), trackingReliable: true, navigating: true), .onCourse)
    }
}
```

- [ ] **Step 2: Create the implementation file**

Create `AISEEBIN/Managers/BeaconPolicy.swift`:

```swift
import Foundation

/// Which side of the walker the route lies on.
enum BeaconSide: Equatable {
    case left, right
}

/// What the beacon should sound like right now.
enum BeaconCue: Equatable {
    case silent
    case onCourse
    /// `pan` runs from -1 (hard left) to 1 (hard right).
    case offCourse(side: BeaconSide, pan: Float)
}

/// Decides the beacon cue from the bearing to the aim point. Pure; the only
/// state is the hysteresis, so the cue cannot flicker at the boundary.
///
/// Two states rather than a continuous slide: a walker learns "high tick =
/// fine, low pattern = turn" in a minute, and the pattern itself says which
/// way (two short = left, one long = right, like the haptics).
struct BeaconPolicy: Equatable {
    /// Off course once the bearing to the aim point exceeds this.
    var offCourseAngle: Float = 25 * .pi / 180
    /// Back on course once the bearing is within this.
    var onCourseAngle: Float = 15 * .pi / 180
    /// Bearing at which the pan reaches full left or right.
    var fullPanAngle: Float = .pi / 2

    private(set) var isOffCourse = false

    mutating func reset() { isOffCourse = false }

    /// `bearing` is the signed angle from the heading to the aim point as
    /// `NavigationGeometry.relativeBearing` gives it: positive = the route is
    /// to the right. `nil` when there is no aim point (arrived).
    mutating func evaluate(bearing: Float?, trackingReliable: Bool, navigating: Bool) -> BeaconCue {
        guard navigating, trackingReliable, let bearing else { return .silent }
        let magnitude = abs(bearing)
        if isOffCourse {
            if magnitude <= onCourseAngle { isOffCourse = false }
        } else if magnitude > offCourseAngle {
            isOffCourse = true
        }
        guard isOffCourse else { return .onCourse }
        let pan = max(-1, min(1, bearing / fullPanAngle))
        return .offCourse(side: bearing < 0 ? .left : .right, pan: pan)
    }
}
```

- [ ] **Step 3: Add the files to the project and run the tests**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN && xcodegen generate 2>&1 | tail -2
```

Then run the test command with `-only-testing:AISEEBINTests/BeaconPolicyTests`.
Expected: all 9 tests pass. (If the test class is "not found", xcodegen did not run; re-run it.)

- [ ] **Step 4: Commit**

```bash
git add AISEEBIN/Managers/BeaconPolicy.swift AISEEBINTests/BeaconPolicyTests.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "BeaconPolicy: on/off-course cue with hysteresis and pan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Turn integrator and device-motion source

**Files:**
- Create: `AISEEBIN/Glasses/BodyHeading.swift`
- Create: `AISEEBINTests/BodyHeadingTests.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Produces:
  - `protocol TurnSource: AnyObject, Sendable { var turn: Float { get }; func start(); func stop() }`
  - `struct TurnIntegrator: Equatable` with `private(set) var turn: Float`, `mutating func reset()`, `mutating func add(rotationRate: SIMD3<Double>, gravity: SIMD3<Double>, time: TimeInterval)`
  - `final class DeviceMotionTurn: TurnSource` (CoreMotion)
  - `final class ScriptedTurn: TurnSource` lives in the test file for Task 4.

- [ ] **Step 1: Write the failing tests**

Create `AISEEBINTests/BodyHeadingTests.swift`:

```swift
import XCTest
import simd
@testable import AISEEBIN

/// `TurnIntegrator` turns device-frame rotation rate and gravity into the
/// body's turn about the vertical, clockwise-positive like the graph heading.
final class BodyHeadingTests: XCTestCase {

    /// Phone upright in a pocket, screen facing forward: gravity along -y.
    private let uprightGravity = SIMD3<Double>(0, -1, 0)

    func testRightTurnIsPositive() {
        var i = TurnIntegrator()
        // A right turn is a clockwise rotation seen from above: negative about world up,
        // and world up is the device +y here, so the rate is about -y.
        i.add(rotationRate: SIMD3(0, -0.5, 0), gravity: uprightGravity, time: 0)
        i.add(rotationRate: SIMD3(0, -0.5, 0), gravity: uprightGravity, time: 2)
        XCTAssertEqual(i.turn, 1.0, accuracy: 1e-6)   // 0.5 rad/s for 2 s, clockwise
    }

    func testLeftTurnIsNegative() {
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(0, 0.5, 0), gravity: uprightGravity, time: 0)
        i.add(rotationRate: SIMD3(0, 0.5, 0), gravity: uprightGravity, time: 1)
        XCTAssertEqual(i.turn, -0.5, accuracy: 1e-6)
    }

    func testSameTurnSameSignWithPhoneUpsideDown() {
        // Upside down: gravity along +y, and the same right turn is now a rotation about +y.
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(0, 0.5, 0), gravity: SIMD3(0, 1, 0), time: 0)
        i.add(rotationRate: SIMD3(0, 0.5, 0), gravity: SIMD3(0, 1, 0), time: 2)
        XCTAssertEqual(i.turn, 1.0, accuracy: 1e-6)
    }

    func testRotationAboutHorizontalAxisDoesNotCount() {
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(2, 0, 0), gravity: uprightGravity, time: 0)   // nodding
        i.add(rotationRate: SIMD3(2, 0, 0), gravity: uprightGravity, time: 1)
        XCTAssertEqual(i.turn, 0, accuracy: 1e-6)
    }

    func testGravityMagnitudeDoesNotScaleTheTurn() {
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: SIMD3(0, -9.81, 0), time: 0)
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: SIMD3(0, -9.81, 0), time: 1)
        XCTAssertEqual(i.turn, 1.0, accuracy: 1e-6)
    }

    func testRepeatedOrBackwardsTimestampsAreIgnored() {
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 5)
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 5)    // duplicate
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 4)    // backwards
        XCTAssertEqual(i.turn, 0, accuracy: 1e-6)
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 6)
        XCTAssertEqual(i.turn, 1.0, accuracy: 1e-6, "5 -> 6 is the only accepted step: ignored samples do not move the clock")
    }

    func testResetStartsFromZero() {
        var i = TurnIntegrator()
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 0)
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 1)
        i.reset()
        XCTAssertEqual(i.turn, 0)
        i.add(rotationRate: SIMD3(0, -1, 0), gravity: uprightGravity, time: 10)
        XCTAssertEqual(i.turn, 0, "first sample after a reset only sets the clock")
    }
}
```

Rule pinned by the last test: **an ignored sample (duplicate or backwards time) does not update the clock**, so the next accepted step is measured from the last accepted time.

- [ ] **Step 2: Create the implementation file**

Create `AISEEBIN/Glasses/BodyHeading.swift`:

```swift
import CoreMotion
import Foundation
import simd

/// The body's turn about the vertical since `start`, in radians,
/// clockwise-positive like the graph heading. Abstracted so positioning can
/// be tested with a scripted turn. 0 when no sensor is available.
protocol TurnSource: AnyObject, Sendable {
    var turn: Float { get }
    func start()
    func stop()
}

/// Pure integrator. The rotation rate projected on gravity, both in the
/// device frame, is the rate of turn about the vertical whatever way the
/// phone sits in a pocket. A right-handed rotation about *up* is a left turn
/// and gravity points *down*, so `ω · ĝ` is clockwise-positive as it is.
struct TurnIntegrator: Equatable {
    private(set) var turn: Float = 0
    private var lastTime: TimeInterval?

    mutating func reset() {
        turn = 0
        lastTime = nil
    }

    /// `rotationRate` in rad/s and `gravity` in any unit, both in the device
    /// frame. A sample whose time is not after the last accepted one is dropped.
    mutating func add(rotationRate: SIMD3<Double>, gravity: SIMD3<Double>, time: TimeInterval) {
        guard let last = lastTime else {
            lastTime = time
            return
        }
        guard time > last else { return }
        let g = simd_length(gravity)
        guard g > 1e-6 else { return }
        let rate = simd_dot(rotationRate, gravity / g)
        turn += Float(rate * (time - last))
        lastTime = time
    }
}

/// `CMMotionManager` device motion at 30 Hz. Needs no permission (unlike the
/// pedometer) and keeps delivering in the background while the app is alive
/// for audio or Bluetooth.
final class DeviceMotionTurn: TurnSource, @unchecked Sendable {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var integrator = TurnIntegrator()

    var turn: Float { lock.withLock { integrator.turn } }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        lock.withLock { integrator.reset() }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let rate = SIMD3(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
            let gravity = SIMD3(data.gravity.x, data.gravity.y, data.gravity.z)
            self.lock.withLock { self.integrator.add(rotationRate: rate, gravity: gravity, time: data.timestamp) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
```

- [ ] **Step 3: Add the files to the project and run the tests**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN && xcodegen generate 2>&1 | tail -2
```

Run the test command with `-only-testing:AISEEBINTests/BodyHeadingTests`. Expected: 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add AISEEBIN/Glasses/BodyHeading.swift AISEEBINTests/BodyHeadingTests.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "BodyHeading: gyro turn about the vertical, clockwise-positive

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Live heading between glasses fixes

**Files:**
- Modify: `AISEEBIN/Glasses/PoseExtrapolator.swift`
- Modify: `AISEEBIN/Glasses/GlassesPositioning.swift` (init, `start`, `stop`, `consume`, `localizeCopied`, `apply`, `tick`)
- Test: `AISEEBINTests/GlassesPositioningLogicTests.swift`

**Interfaces:**
- Consumes: `TurnSource`, `DeviceMotionTurn` (Task 3).
- Produces: `PoseExtrapolator.Fix.turn`, `anchor(position:heading:walked:turn:time:)`, `cameraTransform(walked:turn:)`; `GlassesPositioning.init(pedometer:turnSource:localize:)`.

- [ ] **Step 1: Update the extrapolator tests**

In `AISEEBINTests/GlassesPositioningLogicTests.swift`, the existing extrapolator tests call `anchor(position:heading:walked:time:)` and `cameraTransform(walked:)`. Change every such call to pass a turn of 0:

- `ex.anchor(position: SIMD2(1, 1), heading: .pi / 2, walked: 10, time: 0)` → `ex.anchor(position: SIMD2(1, 1), heading: .pi / 2, walked: 10, turn: 0, time: 0)`
- `ex.anchor(position: .zero, heading: 0, walked: 10, time: 0)` → `..., walked: 10, turn: 0, time: 0)`
- `ex.anchor(position: .zero, heading: 0, walked: 0, time: 100)` → `..., walked: 0, turn: 0, time: 100)`
- `ex.anchor(position: SIMD2(-3, 7), heading: 2.2, walked: 0, time: 0)` → `..., walked: 0, turn: 0, time: 0)`
- `ex.cameraTransform(walked: 1.5)!` → `ex.cameraTransform(walked: 1.5, turn: 0)!`

Then add, after `testTransformRoundTripsThroughNavigationGeometry`:

```swift
    func testHeadingFollowsTurnSinceFix() {
        var ex = PoseExtrapolator()
        ex.anchor(position: .zero, heading: 1.0, walked: 0, turn: 0.3, time: 0)
        // Turned a further 0.5 rad clockwise since the fix: heading 1.5.
        let t = ex.cameraTransform(walked: 0, turn: 0.8)!
        XCTAssertEqual(NavigationGeometry.heading(of: t), 1.5, accuracy: 1e-5)
    }

    func testPositionStillAdvancesAlongFixHeading() {
        var ex = PoseExtrapolator()
        ex.anchor(position: .zero, heading: 0, walked: 0, turn: 0, time: 0)   // facing -z
        let t = ex.cameraTransform(walked: 2, turn: .pi / 2)!                   // turned right since
        let p = NavigationGeometry.planarPosition(of: t)
        XCTAssertEqual(p.x, 0, accuracy: 1e-5)
        XCTAssertEqual(p.y, -2, accuracy: 1e-5, "distance walks along the fix heading; only the heading turns")
    }

    func testReanchorResetsTheOffset() {
        var ex = PoseExtrapolator()
        ex.anchor(position: .zero, heading: 1.0, walked: 0, turn: 0, time: 0)
        _ = ex.cameraTransform(walked: 0, turn: 2.0)
        ex.anchor(position: .zero, heading: 0.2, walked: 0, turn: 2.0, time: 1)
        let t = ex.cameraTransform(walked: 0, turn: 2.0)!
        XCTAssertEqual(NavigationGeometry.heading(of: t), 0.2, accuracy: 1e-5)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:AISEEBINTests/GlassesPositioningLogicTests`. Expected: build errors (`extra argument 'turn'`).

- [ ] **Step 3: Extend `PoseExtrapolator`**

In `AISEEBIN/Glasses/PoseExtrapolator.swift`:

Replace the doc comment paragraph beginning `/// Heading is the *head* direction at the last fix.` with:

```swift
/// Heading is the *head* direction at the last fix plus the body's turn since,
/// from the phone's gyro (`TurnSource`). People mostly look where they walk,
/// so the offset absorbed at the fix is small; the gyro then makes a turn show
/// up in the heading at once instead of at the next fix. Distance still walks
/// along the fix heading.
```

Add `var turn: Float` to `Fix` after `walked`, with the comment `/// Gyro turn (`TurnSource.turn`) at the fix.`:

```swift
    struct Fix: Equatable {
        var position: SIMD2<Float>
        var heading: Float
        /// Pedometer distance at the fix.
        var walked: Float
        /// Gyro turn (`TurnSource.turn`) at the fix.
        var turn: Float
        var time: TimeInterval
    }
```

Change `anchor` to:

```swift
    mutating func anchor(position: SIMD2<Float>, heading: Float, walked: Float, turn: Float, time: TimeInterval) {
        fix = Fix(position: position, heading: heading, walked: walked, turn: turn, time: time)
    }
```

Add a heading accessor and change `cameraTransform`:

```swift
    /// Fix heading plus the body's turn since the fix.
    func heading(turn: Float) -> Float? {
        guard let fix else { return nil }
        return fix.heading + (turn - fix.turn)
    }

    /// A camera transform in the graph frame, as `NavigationGeometry` reads it:
    /// the camera looks down its own −Z, so `heading(of:)` recovers the heading.
    func cameraTransform(walked: Float, turn: Float) -> simd_float4x4? {
        guard let p = position(walked: walked), let h = heading(turn: turn) else { return nil }
        return Self.transform(position: p, heading: h)
    }
```

- [ ] **Step 4: Thread the turn source through `GlassesPositioning`**

In `AISEEBIN/Glasses/GlassesPositioning.swift`:

1. Add a stored source next to the pedometer:
```swift
    @ObservationIgnored private let turnSource: TurnSource
```
2. Change the initializer signature and body:
```swift
    init(pedometer: WalkedDistanceSource = PedometerDistance(),
         turnSource: TurnSource = DeviceMotionTurn(),
         localize: Localize? = nil) {
        self.pedometer = pedometer
        self.turnSource = turnSource
```
3. In `start(alignment:)`, right after `pedometer.start()`, add `turnSource.start()`. In `stop()`, right after `pedometer.stop()`, add `turnSource.stop()`.
4. In `consume(_:)`, after `let walkedAtCapture = pedometer.walkedMetres` add `let turnAtCapture = turnSource.turn`, and pass it: `await self.localizeCopied(frame, capturedAt: now, walkedAtCapture: walkedAtCapture, turnAtCapture: turnAtCapture, generation: generation)`.
5. Add `turnAtCapture: Float` as a parameter of `localizeCopied` (after `walkedAtCapture`) and of `apply` (after `walkedAtCapture walked: Float`, as `turnAtCapture turn: Float`), passing it through the one call between them.
6. In `apply`, change the anchor line to `extrapolator.anchor(position: position, heading: heading, walked: walked, turn: turn, time: capturedAt)` and extend the diagnostics line so the on-device sign check (Task 9) can compare fix heading with gyro turn:
```swift
        DiagnosticsLog.write(String(format: "glasses-immersal fix %d: graph (%.2f, %.2f) heading %.0f deg walked %.1f m gyro %.0f deg", fixes, position.x, position.y, heading * 180 / .pi, walked, turn * 180 / .pi))
```
7. In `tick()`, change the transform line to `guard let transform = extrapolator.cameraTransform(walked: walked, turn: turnSource.turn), let fix = extrapolator.fix else {`.

- [ ] **Step 5: Type-check and run the tests**

Run the type-check command, then the tests with `-only-testing:AISEEBINTests/GlassesPositioningLogicTests`. Expected: all pass. Also run `-only-testing:AISEEBINTests/LocalizerReselectionTests` (it constructs `GlassesPositioning` with a scripted pedometer; the new parameter has a default so it should still compile).

- [ ] **Step 6: Commit**

```bash
git add AISEEBIN/Glasses/PoseExtrapolator.swift AISEEBIN/Glasses/GlassesPositioning.swift AISEEBINTests/GlassesPositioningLogicTests.swift
git commit -m "Glasses: heading between fixes follows the phone's gyro

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Voice command "beeps on / off"

**Files:**
- Modify: `AISEEBIN/Managers/CommandParser.swift`
- Test: `AISEEBINTests/CommandParserTests.swift`

**Interfaces:**
- Produces: `VoiceCommand.beacon(on: Bool)`. Task 8 handles it in the view model.

- [ ] **Step 1: Write the failing tests**

Append inside `final class CommandParserTests`:

```swift
    func testBeepsOnAndOff() {
        XCTAssertEqual(parser.parse("beeps on"), .beacon(on: true))
        XCTAssertEqual(parser.parse("turn on the beep guidance"), .beacon(on: true))
        XCTAssertEqual(parser.parse("beacon on"), .beacon(on: true))
        XCTAssertEqual(parser.parse("turn off the beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("no beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("mute the beacon"), .beacon(on: false))
    }

    func testStopBeepsIsNotStop() {
        XCTAssertEqual(parser.parse("stop beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("stop"), .stop)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

`-only-testing:AISEEBINTests/CommandParserTests`. Expected: build error, `beacon` is not a member of `VoiceCommand`.

- [ ] **Step 3: Implement**

In `AISEEBIN/Managers/CommandParser.swift`:

Add the case to `VoiceCommand` after `case stop`:
```swift
    /// Beep guidance on or off.
    case beacon(on: Bool)
```

Update the doc comment list `/// 1. Global phrases (where am I, nearby, repeat, stop).` to `/// 1. Global phrases (where am I, nearby, repeat, beeps on/off, stop).`

In `parse`, insert **before** the `stop` line:
```swift
        if Self.contains(text, any: ["beep", "beacon"]) {
            let offWords: Set<String> = ["off", "stop", "no", "disable", "mute", "quiet", "silence", "silent"]
            let off = Self.tokens(text).contains { offWords.contains($0) }
            return .beacon(on: !off)
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: all `CommandParserTests` pass. Also type-check the app: the compiler will flag any exhaustive `switch` over `VoiceCommand` outside `NavigationViewModel` (there should be none; `NavigationViewModel.handle(command:)` is fixed in Task 8 — until then, add a temporary `case .beacon: break` there so the app compiles, and replace it in Task 8).

- [ ] **Step 5: Commit**

```bash
git add AISEEBIN/Managers/CommandParser.swift AISEEBINTests/CommandParserTests.swift AISEEBIN/ViewModels/NavigationViewModel.swift
git commit -m "Voice: beeps on / beeps off

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Settable progress-reminder interval

**Files:**
- Modify: `AISEEBIN/Managers/GuidancePolicy.swift`
- Test: `AISEEBINTests/GuidancePolicyTests.swift`

**Interfaces:**
- Produces: `GuidancePolicy.progressReminderInterval: TimeInterval` (var, initialised from the thresholds).

- [ ] **Step 1: Write the failing test**

Append inside `final class GuidancePolicyTests`:

```swift
    func testProgressReminderIntervalCanBeStretched() {
        policy.progressReminderInterval = 30
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 0))
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 12.5))
        XCTAssertEqual(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 30.5),
                       .progress(far))
    }
```

- [ ] **Step 2: Run to verify it fails**

`-only-testing:AISEEBINTests/GuidancePolicyTests`. Expected: build error, no member `progressReminderInterval`.

- [ ] **Step 3: Implement**

In `GuidancePolicy`:

```swift
    let thresholds: GuidanceThresholds
    /// Reassurance cadence; starts at the thresholds' value and is stretched
    /// while the beacon already gives continuous reassurance.
    var progressReminderInterval: TimeInterval
```

In `init(thresholds:)` add `progressReminderInterval = thresholds.progressReminderInterval`. In `evaluate`, change `if now - lastSpeech >= thresholds.progressReminderInterval {` to `if now - lastSpeech >= progressReminderInterval {`.

- [ ] **Step 4: Run to verify it passes**

Expected: all `GuidancePolicyTests` pass.

- [ ] **Step 5: Commit**

```bash
git add AISEEBIN/Managers/GuidancePolicy.swift AISEEBINTests/GuidancePolicyTests.swift
git commit -m "GuidancePolicy: settable progress reminder interval

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: BeaconSynth

**Files:**
- Create: `AISEEBIN/Managers/BeaconSynth.swift`
- Modify: `AISEE-BIN.xcodeproj/project.pbxproj` (via `xcodegen generate`)

**Interfaces:**
- Consumes: `BeaconCue`, `BeaconSide` (Task 2).
- Produces: `@MainActor final class BeaconSynth` with `func apply(_ cue: BeaconCue)`, `func setPaused(_ paused: Bool)`, `func playBoundary()`, `func stop()`, `private(set) var isAvailable: Bool`.

No unit tests: this is audio hardware. It is verified by hand in Task 9. Keep every decision (pattern, cadence, pan) out of it and in `BeaconPolicy`, which is tested.

- [ ] **Step 1: Create the file**

Create `AISEEBIN/Managers/BeaconSynth.swift`:

```swift
import AVFoundation
import Foundation

/// Plays the beacon: a looped, synthesized pattern per `BeaconCue`, panned
/// left or right, on the audio session `GuidanceManager` already configured
/// (A2DP to the glasses, else the loudspeaker). Contains no decisions about
/// *when* to sound; `BeaconPolicy` makes those.
///
/// Each pattern is one period of audio (beeps then silence) scheduled with
/// `.loops`, so the cadence is sample-accurate and needs no timer, and a
/// change of cue is a stop and a new schedule.
@MainActor
final class BeaconSynth {

    /// False when the engine could not start; the beacon then stays silent.
    private(set) var isAvailable = true

    private let engine = AVAudioEngine()
    private let loop = AVAudioPlayerNode()
    private let oneShot = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let onCourseBuffer: AVAudioPCMBuffer
    private let offLeftBuffer: AVAudioPCMBuffer
    private let offRightBuffer: AVAudioPCMBuffer
    private let boundaryBuffer: AVAudioPCMBuffer

    private var cue: BeaconCue = .silent
    private var paused = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let r = Renderer(format: format)
        // On course: one short high tick every 0.6 s.
        onCourseBuffer = r.period(0.6, notes: [(0, 0.06, 880)])
        // Off course: a low pattern every 1.2 s. Left = two quick ticks, right = one long tone,
        // mirroring the turn haptics (two taps left, one long buzz right).
        offLeftBuffer = r.period(1.2, notes: [(0, 0.06, 440), (0.16, 0.06, 440)])
        offRightBuffer = r.period(1.2, notes: [(0, 0.30, 440)])
        // Boundary: three descending notes, once.
        boundaryBuffer = r.period(0.6, notes: [(0, 0.12, 330), (0.18, 0.12, 277), (0.36, 0.12, 220)])

        engine.attach(loop)
        engine.attach(oneShot)
        engine.connect(loop, to: engine.mainMixerNode, format: format)
        engine.connect(oneShot, to: engine.mainMixerNode, format: format)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { self?.restart() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Output route changed (glasses connected or dropped): the engine stops itself.
            MainActor.assumeIsolated { self?.restart() }
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Control

    /// Idempotent: the same cue twice leaves the loop running untouched.
    func apply(_ cue: BeaconCue) {
        guard cue != self.cue else { return }
        self.cue = cue
        restartLoop()
    }

    /// Pauses while the app speaks or listens; the cue is kept and resumes.
    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        restartLoop()
    }

    /// The corridor earcon, once, centred. The loop stops for it and comes back
    /// on the next `apply`/`setPaused` change (speech follows, which pauses it).
    func playBoundary() {
        guard ensureRunning() else { return }
        loop.stop()
        oneShot.stop()
        oneShot.pan = 0
        oneShot.scheduleBuffer(boundaryBuffer, at: nil, options: [], completionHandler: nil)
        oneShot.play()
    }

    /// Silence and release the engine (route ended, beacon switched off).
    func stop() {
        cue = .silent
        paused = false
        loop.stop()
        oneShot.stop()
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Internals

    private func restart() {
        guard cue != .silent else { return }
        restartLoop()
    }

    private func restartLoop() {
        loop.stop()
        guard !paused, cue != .silent, ensureRunning() else {
            if cue == .silent, engine.isRunning, !oneShot.isPlaying { engine.stop() }
            return
        }
        let buffer: AVAudioPCMBuffer
        let pan: Float
        switch cue {
        case .silent:
            return
        case .onCourse:
            buffer = onCourseBuffer; pan = 0
        case .offCourse(let side, let p):
            buffer = side == .left ? offLeftBuffer : offRightBuffer; pan = p
        }
        loop.pan = pan
        loop.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        loop.play()
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            isAvailable = true
            return true
        } catch {
            print("BeaconSynth: engine failed to start: \(error)")
            isAvailable = false
            return false
        }
    }

    // MARK: - Synthesis

    /// Renders one period of mono PCM: sine notes with a 5 ms ramp at each end so
    /// nothing clicks, then silence to the end of the period.
    private struct Renderer {
        let format: AVAudioFormat
        let amplitude: Float = 0.3

        func period(_ seconds: Double, notes: [(start: Double, duration: Double, hz: Double)]) -> AVAudioPCMBuffer {
            let rate = format.sampleRate
            let frames = AVAudioFrameCount(seconds * rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            let out = buffer.floatChannelData![0]
            for i in 0..<Int(frames) { out[i] = 0 }
            let ramp = Int(0.005 * rate)
            for note in notes {
                let first = Int(note.start * rate)
                let count = Int(note.duration * rate)
                for n in 0..<count where first + n < Int(frames) {
                    let envelope = min(1, Float(n) / Float(ramp), Float(count - n) / Float(ramp))
                    let phase = 2 * Double.pi * note.hz * Double(n) / rate
                    out[first + n] = amplitude * envelope * Float(sin(phase))
                }
            }
            return buffer
        }
    }
}
```

- [ ] **Step 2: Add to the project and type-check**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/AISEE-BIN && xcodegen generate 2>&1 | tail -2
```

Run the type-check command. Expected: no errors (warnings about unused results are fine). Fix anything the compiler flags, keeping the public surface above.

- [ ] **Step 3: Commit**

```bash
git add AISEEBIN/Managers/BeaconSynth.swift AISEE-BIN.xcodeproj/project.pbxproj
git commit -m "BeaconSynth: looped synthesized beacon patterns with pan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Wire the beacon into navigation and Settings

**Files:**
- Modify: `AISEEBIN/ViewModels/NavigationViewModel.swift` (properties, `startNavigation`, `stopNavigation`, `finishNavigation`, `handle(_ snapshot:)`, `handle(command:)`)
- Modify: `AISEEBIN/Views/SettingsView.swift` (new section)

**Interfaces:**
- Consumes: `BeaconPolicy`, `BeaconSynth`, `RouteTracker.aimPoint`, `GuidancePolicy.progressReminderInterval`, `VoiceCommand.beacon`.
- Produces: `NavigationViewModel.beaconEnabled: Bool` (observable, persisted under `guidance.beacon`).

- [ ] **Step 1: Add the state to `NavigationViewModel`**

Under `// MARK: Route state` add:

```swift
    // MARK: Beacon (beep guidance)

    /// Look-ahead along the route the beacon aims at.
    static let beaconLookAhead: Float = 3
    /// Reassurance cadence while the beacon is on.
    static let beaconProgressReminderInterval: TimeInterval = 30
    @ObservationIgnored private var beaconPolicy = BeaconPolicy()
    @ObservationIgnored private let beacon = BeaconSynth()
```

Under `// MARK: UI state` add (next to `var showDebug`):

```swift
    /// Beep guidance: optional, off by default, persisted. Takes effect mid-route.
    var beaconEnabled: Bool = UserDefaults.standard.bool(forKey: "guidance.beacon") {
        didSet {
            guard beaconEnabled != oldValue else { return }
            UserDefaults.standard.set(beaconEnabled, forKey: "guidance.beacon")
            policy.progressReminderInterval = beaconEnabled ? Self.beaconProgressReminderInterval : thresholds.progressReminderInterval
            if !beaconEnabled {
                beacon.stop()
                beaconPolicy.reset()
            }
        }
    }
```

At the end of `init`, after `self.policy = GuidancePolicy(thresholds: thresholds)`, add:

```swift
        if beaconEnabled { self.policy.progressReminderInterval = Self.beaconProgressReminderInterval }
```

- [ ] **Step 2: Route lifecycle**

In `startNavigation()`, after `policy.reset()`, add `beaconPolicy.reset()`.

In `stopNavigation()`, after `guidance.stopSpeaking()`, add:
```swift
        beacon.stop()
        beaconPolicy.reset()
```

In `finishNavigation(at:)`, after `routePath = []`, add:
```swift
        beacon.stop()
        beaconPolicy.reset()
```

- [ ] **Step 3: Per-snapshot update and the boundary earcon**

In `handle(_ snapshot: PoseSnapshot)`, after the line `isOffRoute = snapshot.trackingReliable && tracker.isOffRoute(position: position)`, add:

```swift
        updateBeacon(position: position, heading: heading, tracker: tracker, reliable: snapshot.trackingReliable)
```

Replace the tail of `handle(_:)` from `guard let cue, !recognizer.isListening else { return }` to the end of the method with:

```swift
        guard let cue, !recognizer.isListening else { return }

        if case .offRoute = cue, beaconEnabled {
            // The corridor earcon first, in the beacon's own voice; the words follow it.
            beacon.playBoundary()
            Task { [guidance] in
                try? await Task.sleep(for: .milliseconds(600))
                guidance.deliver(cue)
            }
        } else {
            guidance.deliver(cue)
        }

        switch cue {
        case .arrived(let id):
            finishNavigation(at: selectedDestination?.name ?? id)
        case .offRoute:
            replanRoute(from: position)
        default:
            break
        }
    }

    /// One beacon decision per pose: bearing to the look-ahead point on the
    /// route, silent whenever the pose is not trusted, paused while the app
    /// speaks or listens.
    private func updateBeacon(position: SIMD2<Float>, heading: Float, tracker: RouteTracker, reliable: Bool) {
        guard beaconEnabled else { return }
        let bearing = tracker.aimPoint(from: position, lookAhead: Self.beaconLookAhead).map {
            NavigationGeometry.relativeBearing(from: position, heading: heading, to: $0)
        }
        let cue = beaconPolicy.evaluate(bearing: bearing, trackingReliable: reliable, navigating: isNavigating)
        beacon.apply(cue)
        beacon.setPaused(guidance.isSpeaking || recognizer.isListening)
    }
```

- [ ] **Step 4: Voice command handling**

In `handle(command:)`, replace the temporary `case .beacon: break` from Task 5 (or add, before `case .unknown:`):

```swift
        case .beacon(let on):
            beaconEnabled = on
            guidance.speak(on ? "Beeps on." : "Beeps off.", interrupt: true)
```

In the `.unknown` branch, change the help sentence to:
```swift
                guidance.speak("I didn't catch that. You can say: take me to, where am I, what's nearby, repeat, beeps on, beeps off, or stop. Destinations are: \(names).", interrupt: true)
```

- [ ] **Step 5: Settings toggle**

In `AISEEBIN/Views/SettingsView.swift`, add `guidanceSection` to the form between `immersalSection` and `glassesSection`:

```swift
                immersalSection
                guidanceSection
                glassesSection
```

and the section itself before `// MARK: - Immersal` is fine, or after it:

```swift
    // MARK: - Guidance

    private var guidanceSection: some View {
        Section {
            Toggle("Beep guidance", isOn: $viewModel.beaconEnabled)
        } footer: {
            Text("While a route is active, a steady high tick means you are heading along the route. A low pattern means turn: two short beeps for left, one long beep for right. Silence means your position is not known. Say \"beeps on\" or \"beeps off\" any time.")
        }
    }
```

- [ ] **Step 6: Type-check, run every test class touched so far, then build for the simulator**

Type-check command, then the test command without `-only-testing` (full run; expect everything green), then:

```bash
xcodebuild build -project AISEE-BIN.xcodeproj -scheme AISEEBIN \
  -destination 'platform=iOS Simulator,id=19416412-211F-4CB7-B70B-F0CA5345AA27' 2>&1 | grep -E 'error:|BUILD' | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add AISEEBIN/ViewModels/NavigationViewModel.swift AISEEBIN/Views/SettingsView.swift
git commit -m "Beep guidance: heading beacon wired into navigation, Settings toggle

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: On-device verification and README note

**Files:**
- Modify: `README.md` (one line under the features/guidance description)

- [ ] **Step 1: README**

Find the paragraph in `README.md` that describes guidance (search for "haptic" or "spoken"), and add one sentence: `Optional beep guidance (Settings → Beep guidance, or say "beeps on"): a high tick while you head along the route, a low pattern to turn (two short = left, one long = right), silence when the position is not known.` Commit:

```bash
git add README.md
git commit -m "README: beep guidance

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 2: Install on the iPhone**

Phone udid `00008150-001410210C7A401C`. Build and install a Debug build:

```bash
xcodebuild build -project AISEE-BIN.xcodeproj -scheme AISEEBIN -configuration Debug \
  -destination 'platform=iOS,id=00008150-001410210C7A401C' -allowProvisioningUpdates \
  -derivedDataPath build/dd 2>&1 | grep -E 'error:|BUILD' | tail -3
xcrun devicectl device install app --device 00008150-001410210C7A401C \
  build/dd/Build/Products/Debug-iphoneos/AISEEBIN.app 2>&1 | tail -2
```

- [ ] **Step 3: Hand checks (the user does these; record results in the commit or a note)**

Phone mode, any map with a route (the bundled Greenhouse map works without tracking only in the simulator; on the phone use a scanned map):

1. Settings → Beep guidance on. Start a route. Point the phone along the route: a high tick every 0.6 s. Turn the phone 45° left: two low ticks every 1.2 s. Turn 45° right: one long low tone. Back within 15°: high tick again.
2. Cover the camera until "Relocalizing": the beacon goes silent; uncover: it returns.
3. Say "where am I": the beacon pauses during the sentence and resumes after.
4. Walk 3 m off the path: the three-note earcon, then "You are off route…", then the beacon aims at the new route.
5. Lock the screen with the route running: beacon keeps playing.
6. Say "beeps off": "Beeps off." and silence; "beeps on" restores it.

Glasses mode (phone in a pocket, glasses positioning on, a map with an Immersal alignment):

7. Through the glasses, turning the body left/right swaps the pattern and the side it comes from, immediately, without waiting for a fix.
8. Pull the diagnostics log and check the sign: in consecutive `glasses-immersal fix` lines, the change in `heading` and the change in `gyro` must agree in sign and roughly in size when the wearer turned between fixes.

```bash
xcrun devicectl device copy from --device 00008150-001410210C7A401C --domain-type appDataContainer \
  --domain-identifier com.flowsxr.aiseebin --source Documents/immersal-diag.log \
  --destination /private/tmp/claude-501/-Users-prasanthsasikumar-Documents-GitHub-AISEE-BIN/87f26e23-22a6-4471-9470-b7914e851f61/scratchpad/immersal-diag.log
grep 'glasses-immersal fix' /private/tmp/claude-501/-Users-prasanthsasikumar-Documents-GitHub-AISEE-BIN/87f26e23-22a6-4471-9470-b7914e851f61/scratchpad/immersal-diag.log | tail -20
```

If the signs disagree, the fix is one line in `TurnIntegrator.add`: negate `rate`. Then update `testRightTurnIsPositive`/`testLeftTurnIsNegative` expectations and commit with the log excerpt in the message.
