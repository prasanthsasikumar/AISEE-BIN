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
