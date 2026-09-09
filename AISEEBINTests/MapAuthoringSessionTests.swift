import XCTest
@testable import AISEEBIN

final class MapAuthoringSessionTests: XCTestCase {

    func testAddNodeGeneratesUniqueSlugIDs() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "Orchid Display", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        let b = session.addNode(name: "Orchid Display", category: .exhibit, details: "Second one", position: SIMD2<Float>(1, 1))
        XCTAssertEqual(a.id, "orchid-display")
        XCTAssertEqual(b.id, "orchid-display-2")
        XCTAssertEqual(session.map.pois.count, 2)
    }

    func testRenameChangesOnlyTheMapNameAndKeepsTheGraph() {
        var session = MapAuthoringSession(mapName: "Greenhouse")
        let a = session.addNode(name: "Entrance", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        session.rename(to: "Home")
        XCTAssertEqual(session.map.name, "Home")
        XCTAssertEqual(session.map.pois.map(\.id), [a.id])
    }

    func testConsecutiveNodesAreChainedByAnEdge() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "Entrance", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        let b = session.addNode(name: "Junction", category: .junction, details: nil, position: SIMD2<Float>(0, -8))
        XCTAssertEqual(session.map.edges, [NavigationEdge(from: a.id, to: b.id)])
    }

    func testConnectAddsEdgeWithoutDuplicates() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "A", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        let b = session.addNode(name: "B", category: .destination, details: nil, position: SIMD2<Float>(1, 0))
        let c = session.addNode(name: "C", category: .destination, details: nil, position: SIMD2<Float>(2, 0))
        session.connect(c.id, to: a.id)
        session.connect(a.id, to: c.id) // reverse of an existing undirected edge
        session.connect(a.id, to: b.id) // already chained
        XCTAssertEqual(session.map.edges.count, 3)
    }

    func testRemoveNodeDropsItsEdgesAndDoesNotChainFromIt() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "A", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        let b = session.addNode(name: "B", category: .destination, details: nil, position: SIMD2<Float>(1, 0))
        session.removeNode(b.id)
        let c = session.addNode(name: "C", category: .destination, details: nil, position: SIMD2<Float>(2, 0))
        XCTAssertEqual(session.map.pois.map(\.id), [a.id, c.id])
        XCTAssertEqual(session.map.edges, [NavigationEdge(from: a.id, to: c.id)])
    }

    func testStartingFromExistingMapContinuesChainFromLastNode() {
        var session = MapAuthoringSession(map: SampleGreenhouseMap.map)
        let new = session.addNode(name: "Fern Wall", category: .exhibit, details: nil, position: SIMD2<Float>(6, -6))
        XCTAssertTrue(session.map.edges.contains(NavigationEdge(from: "restrooms", to: new.id)))
    }
}

final class MapAuthoringTrailTests: XCTestCase {

    func testWalkedTrailInsertsWaypointsAtCorners() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "Entrance", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        // Walk 8 m forward, turn right, walk 6 m: an L with one corner at (0,-8).
        var trail = (1...8).map { SIMD2<Float>(0, -Float($0)) }
        trail += (1...5).map { SIMD2<Float>(Float($0), -8) }
        let b = session.addNode(name: "Palm House", category: .destination, details: nil,
                                position: SIMD2<Float>(6, -8), trail: trail)

        XCTAssertEqual(session.map.pois.count, 3)
        let waypoint = session.map.pois[1]
        XCTAssertEqual(waypoint.category, .junction)
        XCTAssertEqual(waypoint.planarPosition, SIMD2<Float>(0, -8))
        XCTAssertEqual(session.map.edges, [NavigationEdge(from: a.id, to: waypoint.id),
                                           NavigationEdge(from: waypoint.id, to: b.id)])
    }

    func testStraightTrailAddsNoWaypoints() {
        var session = MapAuthoringSession(mapName: "Test")
        let a = session.addNode(name: "A", category: .destination, details: nil, position: SIMD2<Float>(0, 0))
        let trail = (1...5).map { SIMD2<Float>(0, -Float($0)) }
        let b = session.addNode(name: "B", category: .destination, details: nil, position: SIMD2<Float>(0, -6), trail: trail)
        XCTAssertEqual(session.map.pois.count, 2)
        XCTAssertEqual(session.map.edges, [NavigationEdge(from: a.id, to: b.id)])
    }
}
