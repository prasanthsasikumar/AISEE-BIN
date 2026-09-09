import XCTest
@testable import AISEEBIN

final class NavigationMapTests: XCTestCase {

    func testJSONRoundTripPreservesAnnotations() throws {
        let poi = NavigationPOI(id: "titan", name: "Titan Arum", x: 1, z: -2,
                                category: .exhibit, details: "Blooms once a decade", aliases: ["corpse flower"])
        let map = NavigationMap(name: "Test", pois: [poi], edges: [])
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(NavigationMap.self, from: data)
        XCTAssertEqual(decoded.pois, [poi])
    }

    func testDecodingOmitsOptionalFieldsWithDefaults() throws {
        let json = #"{"name":"T","pois":[{"id":"a","name":"A","x":0,"z":0}],"edges":[]}"#
        let map = try JSONDecoder().decode(NavigationMap.self, from: Data(json.utf8))
        XCTAssertEqual(map.pois[0].category, .destination)
        XCTAssertEqual(map.pois[0].aliases, [])
        XCTAssertTrue(map.pois[0].isDestination)
    }

    func testCategoryDrivesDestinationAndAnnounceRadius() {
        XCTAssertTrue(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .exhibit).isDestination)
        XCTAssertFalse(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .hazard).isDestination)
        XCTAssertFalse(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .junction).isDestination)
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .hazard).announceRadius, 2.5)
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .destination).announceRadius, 0)
    }
}
