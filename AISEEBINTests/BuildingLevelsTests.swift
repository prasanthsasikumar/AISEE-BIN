import GameplayKit
import XCTest
@testable import AISEEBIN

/// Two stacked floors: a corridor on Level 1 (y ≈ 1.4), stairs and a lift up to
/// a corridor directly above on Level 2 (y ≈ 5.0).
final class BuildingLevelsTests: XCTestCase {

    private func poi(_ id: String, _ name: String, _ x: Float, _ z: Float, y: Float?,
                     _ category: POICategory = .destination) -> NavigationPOI {
        var p = NavigationPOI(id: id, name: name, x: x, z: z, category: category)
        p.y = y
        return p
    }

    private var twoFloors: NavigationMap {
        NavigationMap(name: "nus-test", pois: [
            poi("entrance", "Entrance", 0, 0, y: 1.4),
            poi("wp-1", "Waypoint 1", 5, 0, y: nil, .junction),
            poi("stairs-1", "Stairs bottom", 10, 0, y: 1.3, .junction),
            poi("stairs-2", "Stairs top", 10, -3, y: 5.0, .junction),
            poi("lab", "Robotics Lab", 0, -3, y: 5.1),
            poi("lift-1", "Lift L1", 2, 2, y: 1.4, .junction),
            poi("lift-2", "Lift L2", 2, 2, y: 5.0, .junction),
            poi("cafe", "Cafe", 0, -0.5, y: 1.5),
        ], edges: [
            NavigationEdge(from: "entrance", to: "wp-1"),
            NavigationEdge(from: "wp-1", to: "stairs-1"),
            NavigationEdge(from: "stairs-1", to: "stairs-2"),
            NavigationEdge(from: "stairs-2", to: "lab"),
            NavigationEdge(from: "entrance", to: "lift-1"),
            NavigationEdge(from: "lift-1", to: "lift-2"),
            NavigationEdge(from: "lift-2", to: "lab"),
            NavigationEdge(from: "entrance", to: "cafe"),
        ])
    }

    func testHeightRoundTripsAndIsOptional() throws {
        let data = try JSONEncoder().encode(twoFloors)
        let back = try JSONDecoder().decode(NavigationMap.self, from: data)
        XCTAssertEqual(back.pois.first { $0.id == "lab" }?.y, 5.1)
        XCTAssertNil(back.pois.first { $0.id == "wp-1" }?.y)
        let old = #"{"name":"m","pois":[{"id":"a","name":"A","x":1,"z":2}],"edges":[]}"#
        XCTAssertNil(try JSONDecoder().decode(NavigationMap.self, from: Data(old.utf8)).pois[0].y)
    }

    func testLevelsClusterAndWaypointsInherit() {
        let levels = BuildingLevels(map: twoFloors)
        XCTAssertEqual(levels.levelHeights.count, 2)
        XCTAssertTrue(levels.isMultiLevel)
        XCTAssertEqual(levels.level(of: "entrance"), 1)
        XCTAssertEqual(levels.level(of: "lab"), 2)
        XCTAssertEqual(levels.level(of: "wp-1"), 1)
        XCTAssertEqual(levels.levelName(of: "lab"), "Level 2")
        XCTAssertEqual(levels.level(forHeight: 4.6), 2)
    }

    func testMapWithoutHeightsIsOneLevel() {
        var map = twoFloors
        for i in map.pois.indices { map.pois[i].y = nil }
        let levels = BuildingLevels(map: map)
        XCTAssertFalse(levels.isMultiLevel)
        XCTAssertNil(levels.levelName(of: "lab"))
        XCTAssertNil(levels.levelChange(from: "stairs-1", to: "stairs-2"))
    }

    func testLevelChangeKindAndText() {
        let levels = BuildingLevels(map: twoFloors)
        XCTAssertEqual(levels.levelChange(from: "stairs-1", to: "stairs-2"), .stairs)
        XCTAssertEqual(levels.levelChange(from: "lift-1", to: "lift-2"), .lift)
        XCTAssertNil(levels.levelChange(from: "entrance", to: "wp-1"))
        XCTAssertEqual(levels.levelChangeText(from: "stairs-1", to: "stairs-2"), "Take the stairs up to Level 2")
        XCTAssertEqual(levels.levelChangeText(from: "lift-2", to: "lift-1"), "Take the lift down to Level 1")
    }

    func testNearestNodeStaysOnYourFloor() {
        let engine = PathfindingEngine(map: twoFloors)
        // Standing on Level 2 right above the Cafe: planar nearest is the Cafe (0.5 m), but it is a floor down.
        let node = engine.nearestNode(to: SIMD2(0, -1), height: 5.0)
        XCTAssertEqual(engine.name(of: node!), "lab")
        // Same spot on Level 1 picks the Cafe.
        XCTAssertEqual(engine.name(of: engine.nearestNode(to: SIMD2(0, -1), height: 1.4)!), "cafe")
        // No height: planar, as before.
        XCTAssertEqual(engine.name(of: engine.nearestNode(to: SIMD2(0, -1), height: nil)!), "cafe")
    }

    func testTrackerWaitsForTheClimb() {
        let engine = PathfindingEngine(map: twoFloors)
        let path = ["stairs-1", "stairs-2", "lab"].compactMap { engine.node(named: $0) }
        var tracker = RouteTracker(path: path, thresholds: GuidanceThresholds(arrivalDistance: 3.5),
                                   heights: engine.levels.heights)
        // At the stairs bottom, within planar reach of the top: not reached until you are up there.
        XCTAssertEqual(tracker.update(position: SIMD2(10, -1), height: 1.3), .none)
        XCTAssertEqual(tracker.update(position: SIMD2(10, -2), height: 4.9), .reachedNode("stairs-2"))
    }

    func testGuideWalksAheadAndClimbs() {
        let stops: [GuidePlacement.Stop] = [
            .init(planar: SIMD2(4, 0), floorY: 0),
            .init(planar: SIMD2(4, -4), floorY: 3.6),
        ]
        let flat = GuidePlacement.place(from: SIMD2(0, 0), userFloorY: 0, stops: stops, lookAhead: 2.5)!
        XCTAssertEqual(flat.position.x, 2.5, accuracy: 1e-4)
        XCTAssertEqual(flat.position.y, 0, accuracy: 1e-4)
        XCTAssertFalse(flat.waiting)
        let climbing = GuidePlacement.place(from: SIMD2(3, 0), userFloorY: 0, stops: stops, lookAhead: 3)!
        XCTAssertEqual(climbing.position.z, -2, accuracy: 1e-4)
        XCTAssertEqual(climbing.position.y, 1.8, accuracy: 1e-4)
        XCTAssertEqual(climbing.facing, SIMD2(0, -1))
    }

    func testGuideHoldsAtTheLiftDoor() {
        let stops: [GuidePlacement.Stop] = [
            .init(planar: SIMD2(1, 0), floorY: 0, holdHere: true),
            .init(planar: SIMD2(1, 0), floorY: 3.6),
            .init(planar: SIMD2(5, 0), floorY: 3.6),
        ]
        let r = GuidePlacement.place(from: SIMD2(0, 0), userFloorY: 0, stops: stops, lookAhead: 2.5)!
        XCTAssertEqual(r.position, SIMD3(1, 0, 0))
        XCTAssertTrue(r.waiting)
    }
}

final class NUSMapFilterTests: XCTestCase {
    private func summary(_ slug: String, _ t: TimeInterval) -> RemoteMapSummary {
        let json = #"{"mapSlug":"\#(slug)","name":"\#(slug)","version":1,"source":"ios","pointCount":0,"createdAt":\#(t)}"#
        return try! JSONDecoder().decode(RemoteMapSummary.self, from: Data(json.utf8))
    }

    func testEachAppListsItsOwnMaps() {
        XCTAssertTrue(ServerConfig.lists(slug: "nus-hub", nusApp: true))
        XCTAssertFalse(ServerConfig.lists(slug: "labeltransfertest", nusApp: true))
        XCTAssertFalse(ServerConfig.lists(slug: "nus-hub", nusApp: false))
        XCTAssertTrue(ServerConfig.lists(slug: "labeltransfertest", nusApp: false))
    }

    func testNUSStarterIsTheNewestNUSMap() {
        let maps = [summary("nus-old", 10), summary("labeltransfertest", 99), summary("nus-new", 20)]
        XCTAssertEqual(ServerConfig.starterSlug(from: maps, nusApp: true), "nus-new")
        XCTAssertEqual(ServerConfig.starterSlug(from: maps, nusApp: false), ServerConfig.starterMapSlug)
        XCTAssertNil(ServerConfig.starterSlug(from: [summary("x", 1)], nusApp: true))
    }
}
