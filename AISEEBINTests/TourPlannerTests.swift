import XCTest
@testable import AISEEBIN

final class TourPlannerTests: XCTestCase {

    /// S—a—b—c—E in a straight line, 10 m apart; every stop is a 3-minute exhibit.
    private func lineMap(edit: (inout NavigationMap) -> Void = { _ in }) -> NavigationMap {
        let ids = ["S", "a", "b", "c", "E"]
        let pois = ids.enumerated().map { i, id in
            NavigationPOI(id: id, name: id.uppercased(), x: Float(i) * 10, z: 0, category: .exhibit)
        }
        let edges = zip(ids, ids.dropFirst()).map { NavigationEdge(from: $0, to: $1) }
        var map = NavigationMap(name: "Line", pois: pois, edges: edges)
        map.tourStart = "S"
        map.tourEnd = "E"
        edit(&map)
        return map
    }

    func testTwentyMinutesFitsBudget() {
        let plan = TourPlanner(map: lineMap()).plan(TourRequest(minutes: 20))!
        XCTAssertLessThanOrEqual(plan.totalMinutes, 18)
        XCTAssertFalse(plan.stopIDs.isEmpty)
    }

    func testTinyBudgetGoesStraightToEnd() {
        let plan = TourPlanner(map: lineMap()).plan(TourRequest(minutes: 1))!
        XCTAssertEqual(plan.stopIDs, [])
        XCTAssertEqual(plan.startID, "S")
        XCTAssertEqual(plan.endID, "E")
        XCTAssertEqual(plan.walkMinutes, 40.0 / 0.7 / 60, accuracy: 0.01)
    }

    func testMustSeeAlwaysIncluded() {
        let plan = TourPlanner(map: lineMap()).plan(TourRequest(minutes: 1, mustSee: ["c"]))!
        XCTAssertEqual(plan.stopIDs, ["c"])
    }

    func testHighlightZeroExcluded() {
        let map = lineMap { $0.pois[2].highlight = 0 }
        let planner = TourPlanner(map: map)
        XCTAssertFalse(planner.candidates.map(\.id).contains("b"))
        XCTAssertFalse(planner.plan(TourRequest(minutes: 120))!.stopIDs.contains("b"))
    }

    func testStartFallsBackToEntranceThenEndToStart() {
        let map = NavigationMap(name: "M", pois: [
            NavigationPOI(id: "entrance", name: "Entrance", x: 0, z: 0, category: .destination),
            NavigationPOI(id: "x", name: "X", x: 10, z: 0, category: .exhibit),
        ], edges: [NavigationEdge(from: "entrance", to: "x")])
        let planner = TourPlanner(map: map)
        XCTAssertEqual(planner.startID, "entrance")
        XCTAssertEqual(planner.endID, "entrance")
        XCTAssertEqual(planner.plan(TourRequest(minutes: 30))!.stopIDs, ["x"])
    }

    func testOrderFollowsTheLine() {
        XCTAssertEqual(TourPlanner(map: lineMap()).plan(TourRequest(minutes: 60))!.stopIDs, ["a", "b", "c"])
    }

    func testRemovingAndAddingRecompute() {
        let planner = TourPlanner(map: lineMap())
        let full = planner.plan(TourRequest(minutes: 60))!
        let without = planner.removing("b", from: full)
        XCTAssertEqual(without.stopIDs, ["a", "c"])
        XCTAssertEqual(without.dwellMinutes, full.dwellMinutes - 3, accuracy: 0.001)
        XCTAssertEqual(planner.adding("b", to: without).stopIDs, ["a", "b", "c"])
    }

    func testInterestsPreferMatchingTags() {
        let map = lineMap {
            $0.pois[3].tags = ["orchids"]   // c
            $0.pois[1].highlight = 1        // a outranks b and c on its own
        }
        // Room for exactly one stop beyond the walk (40 m ≈ 0.95 min walk + 3 min dwell ≤ 4.5).
        let plan = TourPlanner(map: map).plan(TourRequest(minutes: 5, interests: ["Orchid"]))!
        XCTAssertEqual(plan.stopIDs, ["c"])
    }

    func testUnreachableExhibitIgnored() {
        let map = lineMap { $0.pois.append(NavigationPOI(id: "z", name: "Z", x: 99, z: 99, category: .exhibit)) }
        XCTAssertFalse(TourPlanner(map: map).candidates.map(\.id).contains("z"))
    }

    func testNoStartReturnsNil() {
        let map = NavigationMap(name: "J", pois: [NavigationPOI(id: "j", name: "J", x: 0, z: 0, category: .junction)], edges: [])
        XCTAssertNil(TourPlanner(map: map).plan(TourRequest(minutes: 20)))
    }
}
