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
        policy.reset()   // a fresh route: no held side
        guard case .offCourse(let side, let left) = policy.evaluate(bearing: deg(-179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(left, -1)
        XCTAssertEqual(side, .left)
        policy.reset()
        guard case .offCourse(let side2, _) = policy.evaluate(bearing: deg(179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(side2, .right)
    }

    func testResetClearsOffCourse() {
        _ = policy.evaluate(bearing: deg(60), trackingReliable: true, navigating: true)
        policy.reset()
        XCTAssertFalse(policy.isOffCourse)
        XCTAssertEqual(policy.evaluate(bearing: deg(20), trackingReliable: true, navigating: true), .onCourse)
    }

    // MARK: - Side hold behind the walker

    func testSideIsHeldAcrossTheSeamBehindTheWalker() {
        guard case .offCourse(let first, _) = policy.evaluate(bearing: deg(179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(first, .right)
        // The aim point is straight behind and the bearing jitters across ±180°: keep the side.
        guard case .offCourse(let held, _) = policy.evaluate(bearing: deg(-179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(held, .right)
        // Clearly to the left again: the sign rules.
        guard case .offCourse(let left, _) = policy.evaluate(bearing: deg(-100), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(left, .left)
    }

    func testFirstBearingBehindUsesItsOwnSign() {
        guard case .offCourse(let side, _) = policy.evaluate(bearing: deg(-179.9), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(side, .left)
    }

    func testOnCourseForgetsTheHeldSide() {
        _ = policy.evaluate(bearing: deg(179.9), trackingReliable: true, navigating: true)   // held right
        _ = policy.evaluate(bearing: deg(5), trackingReliable: true, navigating: true)       // on course
        guard case .offCourse(let side, _) = policy.evaluate(bearing: deg(-170), trackingReliable: true, navigating: true) else { return XCTFail() }
        XCTAssertEqual(side, .left)
    }
}

/// The audible pattern is what decides whether the loop restarts; pan changes
/// every frame and must not.
final class BeaconCuePatternTests: XCTestCase {

    func testPanDoesNotChangeThePattern() {
        XCTAssertEqual(BeaconCue.offCourse(side: .left, pan: -0.3).pattern, BeaconCue.offCourse(side: .left, pan: -0.9).pattern)
    }

    func testSideChangesThePattern() {
        XCTAssertNotEqual(BeaconCue.offCourse(side: .left, pan: -0.5).pattern, BeaconCue.offCourse(side: .right, pan: 0.5).pattern)
    }

    func testEachStateHasItsOwnPattern() {
        XCTAssertEqual(BeaconCue.silent.pattern, .silent)
        XCTAssertEqual(BeaconCue.onCourse.pattern, .onCourse)
        XCTAssertEqual(BeaconCue.offCourse(side: .left, pan: 0).pattern, .offCourseLeft)
        XCTAssertEqual(BeaconCue.offCourse(side: .right, pan: 0).pattern, .offCourseRight)
    }

    func testPanOfACue() {
        XCTAssertEqual(BeaconCue.offCourse(side: .right, pan: 0.4).pan, 0.4)
        XCTAssertEqual(BeaconCue.onCourse.pan, 0)
        XCTAssertEqual(BeaconCue.silent.pan, 0)
    }
}

/// A beacon nobody feeds must fall silent: when poses stop (ARKit interrupted,
/// app in the background) there is no position behind the sound.
final class BeaconWatchdogTests: XCTestCase {

    func testNeverFedIsNotStarved() {
        XCTAssertFalse(BeaconWatchdog().isStarved(at: 100))
    }

    func testStarvesAfterTheInterval() {
        var w = BeaconWatchdog(starveAfter: 1)
        w.feed(at: 10)
        XCTAssertFalse(w.isStarved(at: 10.9))
        XCTAssertTrue(w.isStarved(at: 11.1))
    }

    func testFeedingAgainClearsStarvation() {
        var w = BeaconWatchdog(starveAfter: 1)
        w.feed(at: 10)
        XCTAssertTrue(w.isStarved(at: 12))
        w.feed(at: 12)
        XCTAssertFalse(w.isStarved(at: 12.5))
    }

    func testResetForgetsTheLastFeed() {
        var w = BeaconWatchdog(starveAfter: 1)
        w.feed(at: 10)
        w.reset()
        XCTAssertFalse(w.isStarved(at: 50))
    }
}
