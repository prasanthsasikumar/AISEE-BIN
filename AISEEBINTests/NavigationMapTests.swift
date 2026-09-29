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

    func testCustomAnnounceRadiusFromEditor() throws {
        let json = #"{"id":"t","name":"Titan","x":0,"z":0,"category":"exhibit","announceRadius":1.25}"#
        let poi = try JSONDecoder().decode(NavigationPOI.self, from: Data(json.utf8))
        XCTAssertEqual(poi.announceRadius, 1.25)
        // Round-trips under the same key, and stays absent when unset.
        let encoded = String(decoding: try JSONEncoder().encode(poi), as: UTF8.self)
        XCTAssertTrue(encoded.contains(#""announceRadius":1.25"#), encoded)
        let plain = String(decoding: try JSONEncoder().encode(NavigationPOI(id: "a", name: "A", x: 0, z: 0)), as: UTF8.self)
        XCTAssertFalse(plain.contains("announceRadius"), plain)
    }

    func testCustomAnnounceRadiusOnlyForAnnouncedCategoriesAndInRange() {
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .destination, customAnnounceRadius: 4).announceRadius, 0)
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .hazard, customAnnounceRadius: 4).announceRadius, 4)
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .hazard, customAnnounceRadius: 0).announceRadius, 2.5)
        XCTAssertEqual(NavigationPOI(id: "a", name: "A", x: 0, z: 0, category: .hazard, customAnnounceRadius: 500).announceRadius, 2.5)
    }
}
