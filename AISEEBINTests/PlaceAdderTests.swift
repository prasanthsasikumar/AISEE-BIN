import XCTest
@testable import AISEEBIN

/// Places added on site from the Field Test sheet: an id from the name that
/// no other place has, and the edit that puts the new places and their path
/// into whatever the newest server version is by then.
final class PlaceAdderTests: XCTestCase {

    private func poi(_ id: String, _ name: String, x: Float = 0, z: Float = 0) -> NavigationPOI {
        NavigationPOI(id: id, name: name, x: x, z: z)
    }

    // MARK: - Ids

    func testIDIsTheSlugOfTheName() {
        XCTAssertEqual(PlaceAdder.id(for: "Door B", taken: []), "door-b")
        XCTAssertEqual(PlaceAdder.id(for: "  Point 1  ", taken: []), "point-1")
    }

    func testIDFallsBackWhenTheNameHasNoLettersOrDigits() {
        XCTAssertEqual(PlaceAdder.id(for: "!!!", taken: []), "place")
    }

    func testIDIsNumberedPastTakenOnes() {
        XCTAssertEqual(PlaceAdder.id(for: "Door B", taken: ["door-b"]), "door-b-2")
        XCTAssertEqual(PlaceAdder.id(for: "Door B", taken: ["door-b", "door-b-2"]), "door-b-3")
    }

    // MARK: - Applying to a map

    func testApplyAppendsPlacesAndTheirPath() {
        var graph = NavigationMap(name: "m", pois: [poi("a", "A")], edges: [])
        let b = poi("b", "B", x: 1, z: 2), c = poi("c", "C", x: 3, z: 4)
        PlaceAdder.apply(places: [b, c], edges: [NavigationEdge(from: "b", to: "c")], to: &graph)
        XCTAssertEqual(graph.pois.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(graph.pois[1].x, 1); XCTAssertEqual(graph.pois[2].z, 4)
        XCTAssertEqual(graph.edges, [NavigationEdge(from: "b", to: "c")])
    }

    func testApplyRenumbersAnIDTakenMeanwhileAndTheEdgeFollows() {
        // Someone published a different "door-b" while this phone was walking.
        var graph = NavigationMap(name: "m", pois: [poi("door-b", "Door B (editor)")], edges: [])
        let mine = poi("door-b", "Door B", x: 5, z: 5), c = poi("door-c", "Door C")
        PlaceAdder.apply(places: [mine, c], edges: [NavigationEdge(from: "door-b", to: "door-c")], to: &graph)
        XCTAssertEqual(graph.pois.map(\.id), ["door-b", "door-b-2", "door-c"])
        XCTAssertEqual(graph.pois[1].name, "Door B")
        XCTAssertEqual(graph.pois[1].x, 5)
        XCTAssertEqual(graph.edges, [NavigationEdge(from: "door-b-2", to: "door-c")])
    }

    func testApplyKeepsEveryOtherFieldOfARenumberedPlace() {
        var graph = NavigationMap(name: "m", pois: [poi("steps", "Steps")], edges: [])
        let hazard = NavigationPOI(id: "steps", name: "Steps", x: 1, z: 1, category: .hazard, details: "Three steps down",
                                   aliases: ["stairs"], customAnnounceRadius: 4)
        PlaceAdder.apply(places: [hazard], edges: [], to: &graph)
        let added = graph.pois[1]
        XCTAssertEqual(added.id, "steps-2")
        XCTAssertEqual(added.category, .hazard)
        XCTAssertEqual(added.details, "Three steps down")
        XCTAssertEqual(added.aliases, ["stairs"])
        XCTAssertEqual(added.customAnnounceRadius, 4)
    }

    func testApplySkipsAnEdgeThatIsAlreadyThereOrDangles() {
        var graph = NavigationMap(name: "m", pois: [poi("a", "A"), poi("b", "B")], edges: [NavigationEdge(from: "a", to: "b")])
        PlaceAdder.apply(places: [poi("c", "C")],
                         edges: [NavigationEdge(from: "b", to: "a"), NavigationEdge(from: "c", to: "nowhere"), NavigationEdge(from: "b", to: "c")],
                         to: &graph)
        XCTAssertEqual(graph.edges, [NavigationEdge(from: "a", to: "b"), NavigationEdge(from: "b", to: "c")])
    }
}
