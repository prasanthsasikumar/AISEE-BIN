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
