import XCTest
@testable import AISEEBIN

final class GuidancePolicyTests: XCTestCase {

    private var policy: GuidancePolicy!
    private let far = NavigationInstruction(direction: .straight, distance: 9, nextNodeName: "Junction", isFinal: false)
    private let near = NavigationInstruction(direction: .right, distance: 2.5, nextNodeName: "Junction", isFinal: false)

    override func setUp() {
        super.setUp()
        policy = GuidancePolicy(thresholds: GuidanceThresholds())
    }

    func testApproachCueFiresOnceWhenEnteringApproachRadius() {
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 0))
        XCTAssertEqual(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 1),
                       .approaching(near))
        // Still inside the radius a second later: must not repeat.
        XCTAssertNil(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 2))
    }

    func testProgressReminderRespectsInterval() {
        let interval = GuidanceThresholds().progressReminderInterval
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 0))
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: interval - 1))
        XCTAssertEqual(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: interval + 0.5),
                       .progress(far))
    }

    func testNodeReachedIsNeverThrottled() {
        _ = policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 1) // spoke just now
        XCTAssertEqual(policy.evaluate(instruction: far, routeEvent: .reachedNode("junction"), isOffRoute: false, trackingReliable: true, now: 1.2),
                       .nodeReached(far))
    }

    func testArrivalCueWinsOverEverything() {
        XCTAssertEqual(policy.evaluate(instruction: near, routeEvent: .arrived("Orchid Display"), isOffRoute: true, trackingReliable: false, now: 0),
                       .arrived("Orchid Display"))
    }

    func testOffRouteCueIsRateLimited() {
        let repeatInterval = GuidanceThresholds().offRouteRepeatInterval
        XCTAssertEqual(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: true, trackingReliable: true, now: 0), .offRoute)
        XCTAssertNil(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: true, trackingReliable: true, now: 1))
        XCTAssertEqual(policy.evaluate(instruction: far, routeEvent: .none, isOffRoute: true, trackingReliable: true, now: repeatInterval + 1), .offRoute)
    }

    func testRelocalizingCueSuppressesNavigationSpeech() {
        XCTAssertEqual(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: false, now: 0), .relocalizing)
        XCTAssertNil(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: false, now: 1))
    }

    func testStartingANewRouteResetsApproachMemory() {
        XCTAssertEqual(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 0), .approaching(near))
        policy.reset()
        XCTAssertEqual(policy.evaluate(instruction: near, routeEvent: .none, isOffRoute: false, trackingReliable: true, now: 0), .approaching(near))
    }
}
