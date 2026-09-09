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
