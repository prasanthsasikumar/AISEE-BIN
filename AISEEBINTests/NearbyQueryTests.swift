import XCTest
@testable import AISEEBIN

final class NearbyQueryTests: XCTestCase {

    func testNearbySortsByDistanceExcludesJunctionsAndLimits() {
        let engine = PathfindingEngine(map: SampleGreenhouseMap.map)
        // Stand at the junction (0,-8) facing -Z. Tropical (-6,-8) is 6 m left, Palm (6,-8) 6 m right,
        // Orchid (-6,-14) ~8.5 m, Entrance 8 m behind, Restrooms ~8.5 m behind-right.
        let results = engine.nearby(position: SIMD2<Float>(0, -8), heading: 0, maxDistance: 10, limit: 3)
        XCTAssertEqual(results.map(\.poi.id), ["tropical", "palm", "entrance"])
        XCTAssertEqual(results[0].side, .left)
        XCTAssertEqual(results[1].side, .right)
        XCTAssertEqual(results[2].side, .behind)
        XCTAssertEqual(results[0].distance, 6, accuracy: 0.001)
    }

    func testNearbyRespectsMaxDistance() {
        let engine = PathfindingEngine(map: SampleGreenhouseMap.map)
        XCTAssertTrue(engine.nearby(position: SIMD2<Float>(50, 50), heading: 0, maxDistance: 10, limit: 3).isEmpty)
    }
}
