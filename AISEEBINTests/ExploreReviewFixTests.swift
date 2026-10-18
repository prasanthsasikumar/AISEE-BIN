import XCTest
@testable import AISEEBIN

@MainActor
final class ExploreReviewFixTests: XCTestCase {

    private func makeNav(map: NavigationMap = SampleGreenhouseMap.map) -> NavigationViewModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return NavigationViewModel(map: map, mapStore: MapStore(directory: dir))
    }

    /// Review #1: the logo exit (Explore → Navigate) must hand Navigate back unmuted.
    func testLeavingExploreForNavigateClearsHooks() {
        let nav = makeNav()
        nav.mode = .explore
        nav.quietGuidance = true
        nav.onArrived = { _ in }
        nav.transcriptOverride = { _ in }
        nav.mode = .navigation
        XCTAssertFalse(nav.quietGuidance)
        XCTAssertNil(nav.onArrived)
        XCTAssertNil(nav.transcriptOverride)
    }

    /// Review #2: voice directions speak cues but never bring back beeps or hazard alerts.
    func testVoiceDirectionsKeepBeepsAndAlertsOff() {
        let nav = makeNav()
        let explore = ExploreViewModel(nav: nav)
        explore.enter()
        explore.voiceDirections = true
        XCTAssertTrue(nav.quietGuidance, "beacon and proximity stay off in Explore")
        XCTAssertTrue(nav.speakCuesWhenQuiet)
        explore.voiceDirections = false
        XCTAssertFalse(nav.speakCuesWhenQuiet)
    }

    /// Review #5: a tour that cannot be walked says so instead of a dead button.
    func testUnwalkableTourShowsAMessage() {
        var map = NavigationMap(name: "Broken", pois: [
            NavigationPOI(id: "s", name: "S", x: 0, z: 0, category: .exhibit),
            NavigationPOI(id: "e", name: "E", x: 10, z: 0, category: .exhibit),
        ], edges: [])
        map.tourStart = "s"; map.tourEnd = "e"
        let explore = ExploreViewModel(nav: makeNav(map: map))
        explore.choose(minutes: 20)
        XCTAssertEqual(explore.phase, .welcome)
        XCTAssertEqual(explore.message, ExploreViewModel.unwalkableText)
    }
}

final class VisitClockSkipTests: XCTestCase {
    /// Review #3: after a skip the visitor is not nagged about the next stop straight away.
    func testForgiveClearsCurrentLateness() {
        let t0 = Date(timeIntervalSince1970: 0)
        let plan = TourPlan(startID: "S", endID: "E", stopIDs: ["a", "b"], walkMinutes: 2, dwellMinutes: 6)
        var clock = VisitClock(plan: plan, schedule: [1, 5, 8], startedAt: t0)
        let now = t0.addingTimeInterval(9 * 60)
        XCTAssertEqual(clock.behindBy(now: now, nextIndex: 0), 8, accuracy: 0.001)
        clock.forgive(now: now, nextIndex: 0)
        XCTAssertEqual(clock.behindBy(now: now, nextIndex: 0), 0, accuracy: 0.001)
        XCTAssertEqual(clock.behindBy(now: now.addingTimeInterval(60), nextIndex: 0), 1, accuracy: 0.001)
        XCTAssertEqual(clock.minutesLeft(budget: 20, now: now), 11, accuracy: 0.001, "time left still counts from the start")
    }
}
