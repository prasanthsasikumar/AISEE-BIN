import XCTest
import GameplayKit
@testable import AISEEBIN

final class PathfindingEngineTests: XCTestCase {

    private var engine: PathfindingEngine!

    override func setUp() {
        super.setUp()
        engine = PathfindingEngine(map: SampleGreenhouseMap.map)
    }

    func testFindPathReturnsConnectedNodesFromStartToTarget() {
        let path = engine.findPath(from: "entrance", to: "orchid")
        XCTAssertEqual(path.map(engine.name(of:)), ["entrance", "junction", "tropical", "orchid"])
    }

    func testFindPathPrefersShorterRouteAroundLoop() {
        // Palm Conservatory is reachable via the junction (8 m + 6 m) or via the
        // restrooms (~6.3 m + 6 m). A* must pick the restrooms route.
        let path = engine.findPath(from: "entrance", to: "palm")
        XCTAssertEqual(path.map(engine.name(of:)), ["entrance", "restrooms", "palm"])
    }

    func testFindPathToSelfReturnsSingleNode() {
        let path = engine.findPath(from: "tropical", to: "tropical")
        XCTAssertEqual(path.map(engine.name(of:)), ["tropical"])
    }

    func testFindPathWithUnknownNodeReturnsEmpty() {
        XCTAssertTrue(engine.findPath(from: "entrance", to: "moon-garden").isEmpty)
    }

    func testNearestNodePicksClosestByPlanarDistance() {
        // Just beside the Tropical House at (-6, -8).
        let nearest = engine.nearestNode(to: SIMD2<Float>(-5.2, -7.5))
        XCTAssertEqual(nearest.map(engine.name(of:)), "tropical")
    }

    /// A map edited on the server can carry an edge to a place that no longer
    /// exists (flower-dome-1-oct v2, 2026-10-15). The engine must build without
    /// it and still route over the edges that are whole.
    func testEdgeToAMissingNodeIsIgnored() {
        let a = NavigationPOI(id: "a", name: "A", x: 0, z: 0), b = NavigationPOI(id: "b", name: "B", x: 5, z: 0)
        let map = NavigationMap(name: "m", pois: [a, b],
                                edges: [NavigationEdge(from: "a", to: "b"), NavigationEdge(from: "b", to: "gone")])
        let engine = PathfindingEngine(map: map)
        XCTAssertEqual(engine.findPath(from: "a", to: "b").map(engine.name(of:)), ["a", "b"])
        XCTAssertNil(engine.node(named: "gone"))
    }

    func testDestinationsExcludeIntersectionNodes() {
        let ids = engine.destinations.map(\.id)
        XCTAssertFalse(ids.contains("junction"))
        XCTAssertTrue(ids.contains("orchid"))
    }

    func testGuidanceVectorGivesDistanceAndRightwardAngle() {
        // Camera at origin, facing -Z (ARKit default). Palm Conservatory-like
        // target at x=+3, z=-3 is 45° to the right, 4.24 m away.
        let node = engine.node(named: "restrooms")!
        node.position = vector_float2(3, -3)
        let vector = engine.guidanceVector(from: matrix_identity_float4x4, to: node)
        XCTAssertEqual(vector.distance, 4.2426, accuracy: 0.001)
        XCTAssertEqual(vector.relativeAngle, .pi / 4, accuracy: 0.001)
    }
}
