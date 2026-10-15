import XCTest
import GameplayKit
@testable import AISEEBIN

final class RouteTrackerTests: XCTestCase {

    private let engine = PathfindingEngine(map: SampleGreenhouseMap.map)
    private let thresholds = GuidanceThresholds()

    private func tracker(_ from: String, _ to: String) -> RouteTracker {
        RouteTracker(path: engine.findPath(from: from, to: to), thresholds: thresholds)
    }

    func testFirstTargetIsSecondNodeOnPath() {
        let t = tracker("entrance", "orchid")
        XCTAssertEqual(t.targetNode.map(engine.name(of:)), "junction")
    }

    func testReachingTargetAdvancesToNextNode() {
        var t = tracker("entrance", "orchid")
        let event = t.update(position: SIMD2<Float>(0.3, -7.6)) // within 1.5 m of junction (0, -8)
        XCTAssertEqual(event, .reachedNode("junction"))
        XCTAssertEqual(t.targetNode.map(engine.name(of:)), "tropical")
    }

    func testFarFromTargetEmitsNoEvent() {
        var t = tracker("entrance", "orchid")
        XCTAssertEqual(t.update(position: SIMD2<Float>(0, -2)), .none)
    }

    func testReachingLastNodeEmitsArrived() {
        var t = tracker("entrance", "restrooms")
        let event = t.update(position: SIMD2<Float>(5.5, -1.8))
        XCTAssertEqual(event, .arrived("restrooms"))
        XCTAssertTrue(t.hasArrived)
    }

    func testSingleNodePathIsAlreadyArrived() {
        let t = tracker("orchid", "orchid")
        XCTAssertTrue(t.hasArrived)
    }

    func testOffRouteWhenFarFromCurrentSegment() {
        let t = tracker("entrance", "orchid") // first leg: (0,0) -> (0,-8)
        XCTAssertFalse(t.isOffRoute(position: SIMD2<Float>(1.0, -4)))
        XCTAssertTrue(t.isOffRoute(position: SIMD2<Float>(4.0, -4)))
    }

    func testRemainingDistanceSumsLegAheadAndFollowingEdges() {
        let t = tracker("entrance", "orchid")
        // 6 m left to the junction, then 6 m + 6 m of edges.
        XCTAssertEqual(t.remainingDistance(from: SIMD2<Float>(0, -2)), 18, accuracy: 0.001)
    }

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
}

final class RouteTrackerNamedTargetTests: XCTestCase {

    func testSpokenTargetSkipsJunctionsToNextNamedNode() {
        let engine = PathfindingEngine(map: SampleGreenhouseMap.map)
        // entrance -> junction -> tropical -> orchid: first target is the junction.
        let tracker = RouteTracker(path: engine.findPath(from: "entrance", to: "orchid"), thresholds: GuidanceThresholds())
        XCTAssertEqual(tracker.targetNode.map(engine.name(of:)), "junction")
        XCTAssertEqual(tracker.spokenTargetName, "Tropical House")
    }

    func testSpokenTargetIsTheNodeItselfWhenNamed() {
        let engine = PathfindingEngine(map: SampleGreenhouseMap.map)
        let tracker = RouteTracker(path: engine.findPath(from: "entrance", to: "restrooms"), thresholds: GuidanceThresholds())
        XCTAssertEqual(tracker.spokenTargetName, "Restrooms")
    }
}
