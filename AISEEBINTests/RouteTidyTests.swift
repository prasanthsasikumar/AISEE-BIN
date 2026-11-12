import XCTest
@testable import AISEEBIN

/// The walk produces one chain in walking order. `RouteTidy` turns it into
/// the corridor graph a mapper would otherwise draw by hand in the editor.
final class RouteTidyTests: XCTestCase {

    private func poi(_ id: String, _ x: Float, _ z: Float, _ category: POICategory = .junction, y: Float? = nil) -> NavigationPOI {
        var p = NavigationPOI(id: id, name: id, x: x, z: z, category: category, details: nil)
        p.y = y
        return p
    }

    private func chain(_ pois: [NavigationPOI]) -> NavigationMap {
        NavigationMap(name: "t", pois: pois,
                      edges: zip(pois, pois.dropFirst()).map { NavigationEdge(from: $0.id, to: $1.id) })
    }

    private func links(_ map: NavigationMap) -> Set<String> {
        Set(map.edges.map { [$0.from, $0.to].sorted().joined(separator: "~") })
    }

    /// The AHLab Level 3 walk of 12 Nov 2026 exactly as the app published it
    /// (v3), and the links the mapper then drew by hand (v4).
    func testAHLabWalkBecomesTheHandCleanedGraph() {
        let d = POICategory.destination
        let walked = chain([
            poi("praveen", -0.2, 0.6, d), poi("wp-1", -1.2, 0.1), poi("wp-2", 0.5, -1.7),
            poi("chill-room", 5.6, -0.7, d), poi("think-tank", 3.4, -1.4, d), poi("wp-3", -4.5, -3.6),
            poi("island-table", -7.7, -5.9, d), poi("wp-4", -13.1, -5.7), poi("printer", -13.1, -9.3, d),
            poi("door", -11.0, -10.4, d), poi("wp-5", -14.2, -12.2), poi("gpu-machine", -14.0, -14.3, d),
            poi("wp-6", -16.3, -7.5), poi("taka-ghost", -15.9, -6.2, d), poi("wp-7", -15.1, -10.6),
            poi("wp-8", -16.8, -12.9), poi("sankha", -16.4, -14.2, d),
        ])

        let (tidy, report) = RouteTidy.tidy(walked)

        XCTAssertEqual(links(tidy), [
            "praveen~wp-1", "wp-1~wp-2",
            "think-tank~wp-2", "chill-room~think-tank",      // the out-and-back is a branch off wp-2
            "wp-2~wp-3", "island-table~wp-3", "island-table~wp-4", "printer~wp-4", "door~printer",
            "door~wp-5", "gpu-machine~wp-5", "wp-5~wp-6", "wp-5~wp-8",   // wp-5 and wp-7 are one junction
            "taka-ghost~wp-6", "sankha~wp-8",
        ])
        XCTAssertNil(tidy.pois.first { $0.id == "wp-7" })
        XCTAssertEqual(report.mergedWaypoints, 1)
        XCTAssertGreaterThan(report.reroutedLinks, 0)
        // The merged junction sits between the two it replaces.
        let merged = tidy.pois.first { $0.id == "wp-5" }!
        XCTAssertEqual(merged.x, -14.65, accuracy: 0.01)
        XCTAssertEqual(merged.z, -11.4, accuracy: 0.01)
        // Places end up as dead ends where the walk went out and back.
        for leaf in ["chill-room", "gpu-machine", "taka-ghost"] {
            XCTAssertEqual(tidy.edges.filter { $0.from == leaf || $0.to == leaf }.count, 1, leaf)
        }
    }

    func testACleanCorridorIsLeftAlone() {
        let map = chain([poi("a", 0, 0, .destination), poi("w1", 5, 0), poi("w2", 5, 5), poi("b", 10, 5, .destination)])
        let (tidy, report) = RouteTidy.tidy(map)
        XCTAssertEqual(tidy, map)
        XCTAssertFalse(report.changed)
    }

    func testTidyingTwiceChangesNothingMore() {
        let map = chain([poi("a", 0, 0, .destination), poi("w1", 6, 0), poi("b", 3, 0.4, .destination), poi("w2", -3, 0)])
        let once = RouteTidy.tidy(map).map
        XCTAssertEqual(RouteTidy.tidy(once).map, once)
    }

    func testPlacesAreNeverMergedOnlyWaypoints() {
        let map = chain([poi("a", 0, 0, .destination), poi("b", 1, 0, .exhibit), poi("c", 8, 0, .destination)])
        XCTAssertEqual(RouteTidy.tidy(map).map.pois.map(\.id), ["a", "b", "c"])
    }

    func testNothingJoinsAcrossFloors() {
        // A waypoint and a link directly above each other, 4 m apart in height.
        let map = NavigationMap(name: "t",
                                pois: [poi("a", 0, 0, y: 0), poi("b", 10, 0, y: 0), poi("up", 5, 0.2, y: 4), poi("up2", 5, 9, y: 4)],
                                edges: [NavigationEdge(from: "a", to: "b"), NavigationEdge(from: "up", to: "up2")])
        XCTAssertEqual(RouteTidy.tidy(map).map, map)
    }

    func testDanglingLinksDoNotCrash() {
        let map = NavigationMap(name: "t", pois: [poi("a", 0, 0)], edges: [NavigationEdge(from: "a", to: "gone")])
        XCTAssertEqual(RouteTidy.tidy(map).map.pois.count, 1)
    }
}
