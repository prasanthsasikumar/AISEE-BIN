import XCTest
import simd
@testable import AISEEBIN

final class LocationDescriberTests: XCTestCase {

    // A(0,0) --8m-- W1(0,-8) --6m-- B(6,-8) ; W1 --4m-- W2(-4,-8) --3m-- C(-7,-8)
    private let map = NavigationMap(name: "T", pois: [
        NavigationPOI(id: "a", name: "Main Entrance", x: 0, z: 0),
        NavigationPOI(id: "w1", name: "Waypoint 1", x: 0, z: -8, category: .junction),
        NavigationPOI(id: "b", name: "Window", x: 6, z: -8),
        NavigationPOI(id: "w2", name: "Waypoint 2", x: -4, z: -8, category: .junction),
        NavigationPOI(id: "c", name: "Orchid Display", x: -7, z: -8, category: .exhibit),
    ], edges: [
        NavigationEdge(from: "a", to: "w1"), NavigationEdge(from: "w1", to: "b"),
        NavigationEdge(from: "w1", to: "w2"), NavigationEdge(from: "w2", to: "c"),
    ])

    private var describer: LocationDescriber { LocationDescriber(map: map) }

    func testStandingAtANamedPlace() {
        let d = describer.describe(position: SIMD2<Float>(5.5, -8.4), heading: 0)
        XCTAssertEqual(d, .at(map.pois[2]))
        XCTAssertEqual(d?.spokenText, "You are at the Window.")
    }

    func testStandingNextToAWaypointNeverNamesIt() {
        // 0.5 m from Waypoint 1 on the A–W1 leg, facing -Z (toward W1).
        // Window via W1 is 0.5 + 6 = 6.5 m; Entrance is 7.5 m behind.
        let d = describer.describe(position: SIMD2<Float>(0, -7.5), heading: 0)
        guard case .between(let nearer, let farther, let distance, let side)? = d else {
            return XCTFail("expected between, got \(String(describing: d))")
        }
        XCTAssertEqual(nearer.id, "b")
        XCTAssertEqual(farther.id, "a")
        XCTAssertEqual(distance, 6.5, accuracy: 0.01)
        XCTAssertEqual(side, .ahead)
        XCTAssertFalse(d!.spokenText.contains("Waypoint"))
        XCTAssertEqual(d!.spokenText, "You are between the Window and the Main Entrance, about 7 meters from the Window, ahead.")
    }

    func testBetweenSkipsSeveralWaypoints() {
        // On the W1–W2 leg at (-2,-8): W2 side -> Orchid (2 + 3 = 5), W1 side -> Window (2 + 6 = 8) or Entrance (2 + 8).
        let d = describer.describe(position: SIMD2<Float>(-2, -8), heading: 0)
        guard case .between(let nearer, let farther, let distance, _)? = d else { return XCTFail("expected between") }
        XCTAssertEqual(nearer.id, "c")
        XCTAssertEqual(farther.id, "b")
        XCTAssertEqual(distance, 5, accuracy: 0.01)
    }

    func testFarFromAnyEdgeFallsBackToNearestNamedPlace() {
        let d = describer.describe(position: SIMD2<Float>(20, 5), heading: 0)
        guard case .near(let poi, let distance, _)? = d else { return XCTFail("expected near") }
        XCTAssertEqual(poi.id, "b")
        XCTAssertEqual(distance, 19.1, accuracy: 0.1)
        XCTAssertTrue(d!.spokenText.hasPrefix("You are about 19 meters from the Window"))
    }

    func testMapWithOnlyJunctionsGivesNil() {
        let junctionsOnly = NavigationMap(name: "J", pois: [map.pois[1], map.pois[3]], edges: [NavigationEdge(from: "w1", to: "w2")])
        XCTAssertNil(LocationDescriber(map: junctionsOnly).describe(position: .zero, heading: 0))
    }
}
