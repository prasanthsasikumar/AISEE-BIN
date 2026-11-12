import XCTest
@testable import AISEEBIN

final class CommandParserTests: XCTestCase {

    private let parser = CommandParser(pois: SampleGreenhouseMap.map.pois)

    func testExactDestinationName() {
        XCTAssertEqual(parser.parse("take me to the orchid display"), .navigate(poiID: "orchid"))
    }

    func testFuzzyPluralAndArticles() {
        XCTAssertEqual(parser.parse("go to the orchids"), .navigate(poiID: "orchid"))
        XCTAssertEqual(parser.parse("Navigate to Palm Conservatory please"), .navigate(poiID: "palm"))
    }

    func testAliasMatchesPOI() {
        let pois = [NavigationPOI(id: "restrooms", name: "Restrooms", x: 0, z: 0, aliases: ["bathroom", "toilet"])]
        XCTAssertEqual(CommandParser(pois: pois).parse("where is the bathroom"), .navigate(poiID: "restrooms"))
    }

    func testJunctionsAreNotNavigable() {
        XCTAssertEqual(parser.parse("take me to the central junction"), .unknown)
    }

    func testWhereAmI() {
        XCTAssertEqual(parser.parse("Where am I?"), .whereAmI)
    }

    func testBeepsOnAndOff() {
        XCTAssertEqual(parser.parse("beeps on"), .beacon(on: true))
        XCTAssertEqual(parser.parse("turn on the beep guidance"), .beacon(on: true))
        XCTAssertEqual(parser.parse("beacon on"), .beacon(on: true))
        XCTAssertEqual(parser.parse("turn off the beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("no beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("mute the beacon"), .beacon(on: false))
    }

    func testStopBeepsIsNotStop() {
        XCTAssertEqual(parser.parse("stop beeps"), .beacon(on: false))
        XCTAssertEqual(parser.parse("stop"), .stop)
    }

    func testWhatsNearby() {
        XCTAssertEqual(parser.parse("what's around me"), .whatsNearby)
        XCTAssertEqual(parser.parse("what is nearby"), .whatsNearby)
    }

    func testRepeatAndStop() {
        XCTAssertEqual(parser.parse("repeat"), .repeatInstruction)
        XCTAssertEqual(parser.parse("say that again"), .repeatInstruction)
        XCTAssertEqual(parser.parse("stop navigation"), .stop)
        XCTAssertEqual(parser.parse("cancel"), .stop)
    }

    func testGibberishIsUnknown() {
        XCTAssertEqual(parser.parse("make me a sandwich"), .unknown)
        XCTAssertEqual(parser.parse(""), .unknown)
    }

    // MARK: - Questions

    private let venue = CommandParser(pois: [
        NavigationPOI(id: "orchid", name: "Orchid Display", x: 0, z: 0),
        NavigationPOI(id: "cafe", name: "Cafe", x: 1, z: 0),
    ])

    func testWhatIsThisIsAQuestion() {
        XCTAssertEqual(venue.parse("What is this?"), .question(text: "What is this?"))
    }

    func testAQuestionNamingAPlaceIsAnsweredNotRouted() {
        XCTAssertEqual(venue.parse("what is the orchid display"), .question(text: "what is the orchid display"))
        XCTAssertEqual(venue.parse("tell me about the cafe"), .question(text: "tell me about the cafe"))
        XCTAssertEqual(venue.parse("is the cafe open"), .question(text: "is the cafe open"))
    }

    func testQuestionKeepsTheTranscriptTrimmed() {
        XCTAssertEqual(venue.parse("  Why is it so cold in here  "), .question(text: "Why is it so cold in here"))
    }

    func testAgainInsideAQuestionIsNotRepeat() {
        XCTAssertEqual(venue.parse("can you describe that again"), .question(text: "can you describe that again"))
        XCTAssertEqual(venue.parse("again"), .repeatInstruction)
        XCTAssertEqual(venue.parse("can you repeat that"), .repeatInstruction)
    }

    func testNearbyInsideAQuestionIsNotWhatsNearby() {
        XCTAssertEqual(venue.parse("is there a toilet nearby"), .question(text: "is there a toilet nearby"))
        XCTAssertEqual(venue.parse("what's nearby"), .whatsNearby)
        XCTAssertEqual(venue.parse("what is near me"), .whatsNearby)
        XCTAssertEqual(venue.parse("nearby"), .whatsNearby)
    }

    func testGoThereRequestsStillNavigate() {
        XCTAssertEqual(venue.parse("where is the cafe"), .navigate(poiID: "cafe"))
        XCTAssertEqual(venue.parse("take me to the orchids"), .navigate(poiID: "orchid"))
        XCTAssertEqual(venue.parse("can you take me to the cafe"), .navigate(poiID: "cafe"))
        XCTAssertEqual(venue.parse("how do I get to the cafe"), .navigate(poiID: "cafe"))
        XCTAssertEqual(venue.parse("orchids"), .navigate(poiID: "orchid"))
    }

    func testWhereIsAnUnknownPlaceBecomesAQuestion() {
        XCTAssertEqual(venue.parse("where is the exit"), .question(text: "where is the exit"))
    }

    func testCommandsStillWinOverQuestions() {
        XCTAssertEqual(venue.parse("where am I"), .whereAmI)
        XCTAssertEqual(venue.parse("can you stop"), .stop)
        XCTAssertEqual(venue.parse("stop"), .stop)
    }

    func testNonQuestionGibberishIsStillUnknown() {
        XCTAssertEqual(venue.parse("banana"), .unknown)
        XCTAssertEqual(venue.parse("find my keys"), .unknown)
    }

    func testAFillerWordBeforeAQuestionDoesNotStartARoute() {
        XCTAssertEqual(venue.parse("So what is the orchid display"), .question(text: "So what is the orchid display"))
        XCTAssertEqual(venue.parse("Excuse me, what is the orchid display"),
                       .question(text: "Excuse me, what is the orchid display"))
        XCTAssertEqual(venue.parse("Please tell me about the cafe"), .question(text: "Please tell me about the cafe"))
        XCTAssertEqual(venue.parse("um okay is the cafe open"), .question(text: "um okay is the cafe open"))
    }

    func testAskingToFindAPlaceStillNavigates() {
        XCTAssertEqual(venue.parse("can you find the cafe"), .navigate(poiID: "cafe"))
        XCTAssertEqual(venue.parse("could you help me find the orchids"), .navigate(poiID: "orchid"))
        XCTAssertEqual(venue.parse("please take me to the cafe"), .navigate(poiID: "cafe"))
    }
}
