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
}
