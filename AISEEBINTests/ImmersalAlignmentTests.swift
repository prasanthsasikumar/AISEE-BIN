import XCTest
import simd
@testable import AISEEBIN

/// The alignment is the one number set that lets a phone-authored map guide a
/// glasses wearer. A wrong sign here would put every place on the wrong side.
final class ImmersalAlignmentTests: XCTestCase {

    private let planted = ImmersalAlignment(mapIDs: [151379], yaw: 0.7, tx: 3.5, tz: -2.0,
                                            pairCount: 0, rmsError: 0)

    private func pairs(count: Int, noise: Float = 0) -> [ImmersalAlignment.Pair] {
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { i in
            let angle = Float(i) / Float(count) * 2 * .pi
            let immersal = SIMD2<Float>(6 * cos(angle), 4 * sin(angle))
            var graph = planted.toGraph(immersal)
            if noise > 0 {
                graph += SIMD2(Float.random(in: -noise...noise, using: &rng),
                               Float.random(in: -noise...noise, using: &rng))
            }
            return .init(immersal: immersal, graph: graph)
        }
    }

    func testPerMapPlacementsFromTheEditor() throws {
        let json = #"{"mapIDs":[10,20],"yaw":0,"tx":0,"tz":0,"pairCount":0,"rmsError":0,"maps":[{"id":10,"yaw":0,"tx":0,"tz":0},{"id":20,"yaw":1.5707964,"tx":5,"tz":-2}]}"#
        let a = try JSONDecoder().decode(ImmersalAlignment.self, from: Data(json.utf8))
        // Map 10 is the anchor: identity.
        XCTAssertEqual(a.toGraph(SIMD2(1, 0), mapID: 10), SIMD2(1, 0))
        // Map 20 is rotated a quarter turn and shifted: (1, 0) -> (0, 1) + (5, -2).
        let p = a.toGraph(SIMD2(1, 0), mapID: 20)
        XCTAssertEqual(p.x, 5, accuracy: 1e-5); XCTAssertEqual(p.y, -1, accuracy: 1e-5)
        XCTAssertEqual(a.toGraphHeading(0, mapID: 20), Float.pi / 2, accuracy: 1e-5)
        // The 4×4 agrees with the point form.
        let pose = a.toGraph(cameraPose: simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(1, 0, 0, 1))), mapID: 20)
        XCTAssertEqual(pose.columns.3.x, 5, accuracy: 1e-5); XCTAssertEqual(pose.columns.3.z, -1, accuracy: 1e-5)
        // An unknown map (or none) falls back to the top-level placement.
        XCTAssertEqual(a.toGraph(SIMD2(1, 0), mapID: 99), SIMD2(1, 0))
        XCTAssertTrue(a.isEditorDrawn)
    }

    func testAlignmentsWithoutMapsStillDecode() throws {
        let json = #"{"mapIDs":[151658],"yaw":0,"tx":0,"tz":0,"pairCount":0,"rmsError":0}"#
        let a = try JSONDecoder().decode(ImmersalAlignment.self, from: Data(json.utf8))
        XCTAssertNil(a.maps)
        XCTAssertEqual(a.toGraph(SIMD2(2, 3), mapID: 151658), SIMD2(2, 3))
    }

    func testFitRecoversPlantedTransform() throws {
        let fitted = try ImmersalAlignment.fit(pairs: pairs(count: 12), mapIDs: [151379])
        XCTAssertEqual(fitted.yaw, planted.yaw, accuracy: 1e-4)
        XCTAssertEqual(fitted.tx, planted.tx, accuracy: 1e-3)
        XCTAssertEqual(fitted.tz, planted.tz, accuracy: 1e-3)
        XCTAssertEqual(fitted.rmsError, 0, accuracy: 1e-3)
        XCTAssertEqual(fitted.pairCount, 12)
        XCTAssertEqual(fitted.mapIDs, [151379])
    }

    func testFitReportsResidualUnderNoise() throws {
        let fitted = try ImmersalAlignment.fit(pairs: pairs(count: 40, noise: 0.2), mapIDs: [1])
        XCTAssertEqual(fitted.yaw, planted.yaw, accuracy: 0.05)
        XCTAssertGreaterThan(fitted.rmsError, 0.02)
        XCTAssertLessThan(fitted.rmsError, 0.3)
    }

    func testRefusesTooFewPairs() {
        XCTAssertThrowsError(try ImmersalAlignment.fit(pairs: pairs(count: 5), mapIDs: [1])) { error in
            XCTAssertEqual(error as? ImmersalAlignment.FitError, .tooFewPairs(5))
        }
    }

    func testRefusesClusteredPairs() {
        // Twelve points within 20 cm cannot pin the rotation down.
        let clustered = (0..<12).map { i -> ImmersalAlignment.Pair in
            let p = SIMD2<Float>(Float(i) * 0.01, 0)
            return .init(immersal: p, graph: planted.toGraph(p))
        }
        XCTAssertThrowsError(try ImmersalAlignment.fit(pairs: clustered, mapIDs: [1])) { error in
            guard case .tooLittleSpread = error as? ImmersalAlignment.FitError else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testHeadingRotatesWithPoints() {
        // A step along heading h in Immersal space must be a step along h + yaw in graph space.
        let h: Float = 0.3
        let origin = SIMD2<Float>(1, 2)
        let step = origin + SIMD2(sin(h), -cos(h))
        let delta = planted.toGraph(step) - planted.toGraph(origin)
        let expected = planted.toGraphHeading(h)
        XCTAssertEqual(atan2(delta.x, -delta.y), expected, accuracy: 1e-5)
    }

    func testFullTransformAgreesWithPlanarMath() {
        let pose = PoseExtrapolator.transform(position: SIMD2(2, -3), heading: 1.1)
        let converted = planted.toGraph(cameraPose: pose)
        assertEqual(NavigationGeometry.planarPosition(of: converted), planted.toGraph(SIMD2(2, -3)),
                    accuracy: 1e-5)
        XCTAssertEqual(NavigationGeometry.heading(of: converted), planted.toGraphHeading(1.1), accuracy: 1e-5)
    }

    func testMapJSONRoundTripsWithAndWithoutAlignment() throws {
        var map = SampleGreenhouseMap.map
        let bare = try JSONDecoder().decode(NavigationMap.self, from: JSONEncoder().encode(map))
        XCTAssertNil(bare.immersalAlignment)

        map.immersalAlignment = planted
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(NavigationMap.self, from: data)
        XCTAssertEqual(decoded.immersalAlignment, planted)
        XCTAssertEqual(decoded, map)
    }

    func testHandWrittenJSONWithoutTheFieldStillDecodes() throws {
        let json = #"{"name":"x","pois":[],"edges":[]}"#.data(using: .utf8)!
        let map = try JSONDecoder().decode(NavigationMap.self, from: json)
        XCTAssertNil(map.immersalAlignment)
    }
}

private func assertEqual(_ a: SIMD2<Float>, _ b: SIMD2<Float>, accuracy: Float,
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
}
