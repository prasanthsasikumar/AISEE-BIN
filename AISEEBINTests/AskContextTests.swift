import XCTest
@testable import AISEEBIN

final class AskContextTests: XCTestCase {

    // Heading 0 faces −z (NavigationGeometry), so "ahead" is negative z.
    private let map = NavigationMap(name: "M", pois: [
        NavigationPOI(id: "ahead", name: "Baobab", x: 0, z: -5, category: .exhibit, details: "Old tree"),
        NavigationPOI(id: "behind", name: "Olive", x: 0, z: 8, category: .exhibit),
        NavigationPOI(id: "junction", name: "J", x: 1, z: 0, category: .junction),
        NavigationPOI(id: "far", name: "Far", x: 0, z: -40, category: .exhibit),
        NavigationPOI(id: "side", name: "Side", x: 10, z: 0, category: .destination),
    ], edges: [])

    func testPlacesNearestFirstSkipsJunctions() {
        let places = AskContext.places(map: map, position: .zero, heading: 0)
        XCTAssertEqual(places.map(\.id), ["ahead", "behind", "side"])
        XCTAssertEqual(places[0].details, "Old tree")
        XCTAssertEqual(places[0].distance, 5, accuracy: 0.001)
    }

    func testInViewMarksPlaceAhead() {
        let places = AskContext.places(map: map, position: .zero, heading: 0)
        XCTAssertTrue(places.first { $0.id == "ahead" }!.inView)
        XCTAssertFalse(places.first { $0.id == "behind" }!.inView)
        XCTAssertEqual(places.filter(\.inView).count, 1)
    }

    func testNoPositionGivesNoPlaces() {
        XCTAssertEqual(AskContext.places(map: map, position: nil, heading: 0), [])
    }

    func testRadiusAndLimit() {
        XCTAssertEqual(AskContext.places(map: map, position: .zero, heading: 0, radius: 6).map(\.id), ["ahead"])
        XCTAssertEqual(AskContext.places(map: map, position: .zero, heading: 0, limit: 2).count, 2)
    }

    func testHistoryKeepsThreeRecent() {
        var history = AskHistory()
        let t0 = Date(timeIntervalSince1970: 1000)
        history.add(q: "q1", a: "a1", at: t0)
        history.add(q: "q2", a: "a2", at: t0.addingTimeInterval(10))
        history.add(q: "q3", a: "a3", at: t0.addingTimeInterval(20))
        history.add(q: "q4", a: "a4", at: t0.addingTimeInterval(30))
        XCTAssertEqual(history.recent(now: t0.addingTimeInterval(40)).map(\.q), ["q2", "q3", "q4"])
        // q2 is 301 s old here.
        XCTAssertEqual(history.recent(now: t0.addingTimeInterval(311)).map(\.q), ["q3", "q4"])
    }
}
