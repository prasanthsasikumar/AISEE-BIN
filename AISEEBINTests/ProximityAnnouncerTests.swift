import XCTest
@testable import AISEEBIN

final class ProximityAnnouncerTests: XCTestCase {

    private let titanArum = NavigationPOI(id: "titan", name: "Titan Arum", x: -2, z: -5, category: .exhibit)
    private let step = NavigationPOI(id: "step", name: "Single step down", x: 10, z: -10, category: .hazard)
    private let entrance = NavigationPOI(id: "entrance", name: "Main Entrance", x: 0, z: 0)

    func testRelativeSideBuckets() {
        XCTAssertEqual(RelativeSide(relativeAngle: 0.2), .ahead)
        XCTAssertEqual(RelativeSide(relativeAngle: 1.2), .right)
        XCTAssertEqual(RelativeSide(relativeAngle: -1.2), .left)
        XCTAssertEqual(RelativeSide(relativeAngle: 3.0), .behind)
    }

    func testAnnouncesExhibitOnceWhenEnteringRadius() {
        var announcer = ProximityAnnouncer(pois: [titanArum, step, entrance])
        // Facing -Z at (0,-5): the exhibit at (-2,-5) is 2 m away on the left.
        let first = announcer.update(position: SIMD2<Float>(0, -5), heading: 0)
        XCTAssertEqual(first, [ProximityAnnouncement(poi: titanArum, side: .left, distance: 2)])
        XCTAssertTrue(announcer.update(position: SIMD2<Float>(-0.5, -5), heading: 0).isEmpty)
    }

    func testReArmsAfterLeavingHysteresisRadius() {
        var announcer = ProximityAnnouncer(pois: [titanArum])
        _ = announcer.update(position: SIMD2<Float>(0, -5), heading: 0)
        // Leave to 3 m: inside 1.5×radius, must not re-arm.
        _ = announcer.update(position: SIMD2<Float>(1, -5), heading: 0)
        XCTAssertTrue(announcer.update(position: SIMD2<Float>(0, -5), heading: 0).isEmpty)
        // Leave to 5 m, then return.
        _ = announcer.update(position: SIMD2<Float>(3, -5), heading: 0)
        XCTAssertEqual(announcer.update(position: SIMD2<Float>(0, -5), heading: 0).count, 1)
    }

    func testDestinationsAreNeverAnnounced() {
        var announcer = ProximityAnnouncer(pois: [entrance])
        XCTAssertTrue(announcer.update(position: SIMD2<Float>(0.5, 0), heading: 0).isEmpty)
    }
}
