import XCTest
@testable import AISEEBIN

final class VisitClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 0)
    private let plan = TourPlan(startID: "S", endID: "E", stopIDs: ["a", "b", "c"], walkMinutes: 4, dwellMinutes: 9)
    private let map = NavigationMap(name: "M", pois: [
        { var p = NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .exhibit); p.highlight = 1; return p }(),
        { var p = NavigationPOI(id: "b", name: "B", x: 0, z: 0, category: .exhibit); p.highlight = 3; return p }(),
        { var p = NavigationPOI(id: "c", name: "C", x: 0, z: 0, category: .exhibit); p.highlight = 2; return p }(),
    ], edges: [])
    /// Planned arrival minute at each stop, then at the end.
    private let schedule: [Double] = [4, 8, 12, 14]

    private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    func testMinutesLeftCountsDown() {
        let clock = VisitClock(plan: plan, schedule: schedule, startedAt: t0)
        XCTAssertEqual(clock.minutesLeft(budget: 20, now: minutes(5)), 15, accuracy: 0.001)
    }

    func testNotBehindWhenOnSchedule() {
        var clock = VisitClock(plan: plan, schedule: schedule, startedAt: t0)
        clock.arrived(at: 0, now: minutes(4))
        XCTAssertEqual(clock.behindBy(now: minutes(6), nextIndex: 1), 0, accuracy: 0.001)
        XCTAssertNil(clock.lateOffer(map: map, now: minutes(6), nextIndex: 1))
    }

    func testLateOfferAfterThreeMinutesBehind() {
        let clock = VisitClock(plan: plan, schedule: schedule, startedAt: t0)
        // Stop 0 was due at minute 4; at minute 8 the visitor still has not reached it.
        XCTAssertEqual(clock.behindBy(now: minutes(8), nextIndex: 0), 4, accuracy: 0.001)
        XCTAssertEqual(clock.lateOffer(map: map, now: minutes(8), nextIndex: 0), "b")
        XCTAssertNil(clock.lateOffer(map: map, now: minutes(6.5), nextIndex: 0))
    }

    func testNoLateOfferWithNoRemainingStops() {
        let clock = VisitClock(plan: plan, schedule: schedule, startedAt: t0)
        XCTAssertNil(clock.lateOffer(map: map, now: minutes(30), nextIndex: 3))
    }

    func testScheduleFromPlanner() {
        // S—a—b—E, 7 m apart: each leg is 7 / 0.7 / 60 = 1/6 minute, each stop 3 minutes.
        let ids = ["S", "a", "b", "E"]
        var map = NavigationMap(name: "L",
                                pois: ids.enumerated().map { NavigationPOI(id: $1, name: $1, x: Float($0) * 7, z: 0, category: .exhibit) },
                                edges: zip(ids, ids.dropFirst()).map { NavigationEdge(from: $0, to: $1) })
        map.tourStart = "S"; map.tourEnd = "E"
        let planner = TourPlanner(map: map)
        let plan = planner.evaluate(stopIDs: ["a", "b"])!
        let s = planner.schedule(plan)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0], 1.0 / 6, accuracy: 0.001)
        XCTAssertEqual(s[1], 1.0 / 6 + 3 + 1.0 / 6, accuracy: 0.001)
        XCTAssertEqual(s[2], plan.totalMinutes, accuracy: 0.001)
    }
}
