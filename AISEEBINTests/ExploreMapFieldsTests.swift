import XCTest
@testable import AISEEBIN

final class ExploreMapFieldsTests: XCTestCase {

    func testOldPOIJSONDecodesWithDefaults() throws {
        let json = #"{"id":"a","name":"A","x":0,"z":0,"category":"exhibit"}"#
        let poi = try JSONDecoder().decode(NavigationPOI.self, from: Data(json.utf8))
        XCTAssertEqual(poi.visitMinutes, 3)
        XCTAssertEqual(poi.highlightLevel, 2)
        XCTAssertEqual(poi.tags, [])
        XCTAssertNil(poi.about)
        XCTAssertNil(poi.photo)
    }

    func testNewPOIFieldsRoundTrip() throws {
        var poi = NavigationPOI(id: "o", name: "Orchids", x: 1, z: 2, category: .exhibit)
        poi.minutes = 4.5
        poi.highlight = 0
        poi.tags = ["orchids"]
        poi.about = "x"
        poi.photo = "p.jpg"
        let decoded = try JSONDecoder().decode(NavigationPOI.self, from: JSONEncoder().encode(poi))
        XCTAssertEqual(decoded, poi)
        XCTAssertEqual(decoded.visitMinutes, 4.5)
        XCTAssertEqual(decoded.highlightLevel, 0)
    }

    func testMapTourFieldsRoundTrip() throws {
        var map = NavigationMap(name: "T", pois: [], edges: [])
        map.tourStart = "point-a"
        map.tourEnd = "point-3"
        map.venueInfo = "v"
        let decoded = try JSONDecoder().decode(NavigationMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(decoded.tourStart, "point-a")
        XCTAssertEqual(decoded.tourEnd, "point-3")
        XCTAssertEqual(decoded.venueInfo, "v")
    }

    func testMapWithoutTourFieldsEncodesWithoutKeys() throws {
        let map = NavigationMap(name: "T", pois: [NavigationPOI(id: "a", name: "A", x: 0, z: 0)], edges: [])
        let json = String(decoding: try JSONEncoder().encode(map), as: UTF8.self)
        XCTAssertFalse(json.contains("tourStart"))
        XCTAssertFalse(json.contains("venueInfo"))
        XCTAssertFalse(json.contains("minutes"))
        XCTAssertFalse(json.contains("highlight"))
    }
}
