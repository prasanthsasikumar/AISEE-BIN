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
