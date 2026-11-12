import XCTest
@testable import AISEEBIN

/// Immersal rejects a construct whose name has anything but letters, digits,
/// space and underscore, so the mapper's own name must be cleaned on the way out.
final class ImmersalMapNameTests: XCTestCase {
    func testHyphenBecomesUnderscore() {
        XCTAssertEqual(ImmersalMappingClient.safeName("AHLab-Level3"), "AHLab_Level3")
    }

    func testValidNamesPassUntouched() {
        XCTAssertEqual(ImmersalMappingClient.safeName("Flower Dome_2"), "Flower Dome_2")
    }

    func testPunctuationAndAccentsAreReplacedAndEdgesTrimmed() {
        XCTAssertEqual(ImmersalMappingClient.safeName("Café – Level 3 (east)"), "Caf_ _ Level 3 _east")
    }

    func testNothingUsableFallsBack() {
        XCTAssertEqual(ImmersalMappingClient.safeName("---"), "map")
        XCTAssertEqual(ImmersalMappingClient.safeName(""), "map")
    }
}
