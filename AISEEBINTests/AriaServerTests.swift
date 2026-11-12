import XCTest
import simd
@testable import AISEEBIN

/// The Aria map server option: which localizer it picks, where it posts, and
/// that the bundled test map is usable for routing.
final class AriaServerTests: XCTestCase {

    func testAriaModeUsesTheAriaServerEvenWithoutAToken() {
        let choice = ImmersalLocalizerFactory.make(mapIDs: [AriaTestMap.mapID], token: "", cache: ImmersalMapCache(),
                                                   native: ImmersalNative(), nativeAvailable: true, mode: .ariaServer)
        XCTAssertEqual(choice.localizer.name, "aria server")
        XCTAssertTrue(choice.reason.contains("Aria"), choice.reason)
    }

    func testServerAddressDefaultsAndNormalises() {
        XCTAssertEqual(ImmersalConfig.ariaLocalizeURL(typed: "").absoluteString, "https://loc.flowsxr.com/localizeb64")
        XCTAssertEqual(ImmersalConfig.ariaLocalizeURL(typed: "  ").absoluteString, "https://loc.flowsxr.com/localizeb64")
        XCTAssertEqual(ImmersalConfig.ariaLocalizeURL(typed: "loc.example.com/").absoluteString, "https://loc.example.com/localizeb64")
        XCTAssertEqual(ImmersalConfig.ariaLocalizeURL(typed: "http://10.0.0.5:8100").absoluteString, "http://10.0.0.5:8100/localizeb64")
    }

    func testTestMapIsInTheServerFrameAndFullyRoutable() throws {
        let map = AriaTestMap.map
        let alignment = try XCTUnwrap(map.immersalAlignment)
        XCTAssertEqual(alignment.mapIDs, [AriaTestMap.mapID])
        XCTAssertTrue(alignment.isEditorDrawn, "identity alignment: a server fix is already in the graph frame")
        XCTAssertEqual(alignment.toGraph(SIMD2<Float>(1.5, -2)), SIMD2<Float>(1.5, -2))

        let ids = Set(map.pois.map(\.id))
        XCTAssertEqual(ids.count, map.pois.count, "POI ids are unique")
        for edge in map.edges {
            XCTAssertTrue(ids.contains(edge.from) && ids.contains(edge.to), "\(edge.from)-\(edge.to)")
        }
        // Every place reaches every other: one connected graph.
        var adjacent: [String: Set<String>] = [:]
        for e in map.edges { adjacent[e.from, default: []].insert(e.to); adjacent[e.to, default: []].insert(e.from) }
        var seen: Set<String> = [map.pois[0].id], queue = [map.pois[0].id]
        while let next = queue.popLast() {
            for n in adjacent[next, default: []] where seen.insert(n).inserted { queue.append(n) }
        }
        XCTAssertEqual(seen, ids)
        XCTAssertGreaterThanOrEqual(map.pois.filter(\.isDestination).count, 2)
    }
}
