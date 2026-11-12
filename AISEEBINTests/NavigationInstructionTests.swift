import XCTest
@testable import AISEEBIN

final class NavigationInstructionTests: XCTestCase {

    func testTurnDirectionBucketsFromRelativeAngle() {
        XCTAssertEqual(TurnDirection(relativeAngle: 0.05), .straight)
        XCTAssertEqual(TurnDirection(relativeAngle: 0.5), .slightRight)     // ~29°
        XCTAssertEqual(TurnDirection(relativeAngle: -0.5), .slightLeft)
        XCTAssertEqual(TurnDirection(relativeAngle: 1.4), .right)           // ~80°
        XCTAssertEqual(TurnDirection(relativeAngle: -1.4), .left)
        XCTAssertEqual(TurnDirection(relativeAngle: 2.4), .sharpRight)      // ~137°
        XCTAssertEqual(TurnDirection(relativeAngle: 3.0), .uTurn)           // ~172°
    }

    func testSpokenTextForIntermediateNode() {
        let instruction = NavigationInstruction(direction: .slightRight,
                                                distance: 3.2,
                                                nextNodeName: "Palm Conservatory",
                                                isFinal: false)
        XCTAssertEqual(instruction.spokenText, "Turn slight right. The Palm Conservatory is 3 meters ahead.")
    }

    /// The number spoken and shown is the distance to the place that is named,
    /// not to an unnamed waypoint on the way to it.
    func testSpokenAndShownDistanceIsToTheNamedPlace() {
        let instruction = NavigationInstruction(direction: .straight,
                                                distance: 3.2,          // a waypoint
                                                nextNodeName: "Palm Conservatory",
                                                isFinal: false,
                                                placeDistance: 22.6)
        XCTAssertEqual(instruction.spokenText, "Continue straight. The Palm Conservatory is 23 meters ahead.")
        XCTAssertEqual(instruction.distanceText, "23 m")
        XCTAssertEqual(instruction.nextCueDistanceText, "3 m")
    }

    func testSpokenTextForDestination() {
        let instruction = NavigationInstruction(direction: .straight,
                                                distance: 1.4,
                                                nextNodeName: "Orchid Display",
                                                isFinal: true)
        XCTAssertEqual(instruction.spokenText, "Continue straight. The Orchid Display is 1 meter ahead.")
    }

    func testBannerTextIsShortAndRounded() {
        let instruction = NavigationInstruction(direction: .left,
                                                distance: 7.8,
                                                nextNodeName: "Restrooms",
                                                isFinal: false)
        XCTAssertEqual(instruction.bannerText, "Turn left toward Restrooms")
        XCTAssertEqual(instruction.distanceText, "8 m")
    }
}
