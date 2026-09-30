import XCTest
import simd
@testable import AISEEBIN

final class ScanLinkSolverTests: XCTestCase {

    private func assertClose(_ a: Placement4, _ b: Placement4, metres: Float = 0.01, radians: Float = 0.005,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(NavigationGeometry.wrapAngle(a.yaw - b.yaw), 0, accuracy: radians, "yaw", file: file, line: line)
        XCTAssertEqual(a.tx, b.tx, accuracy: metres, "tx", file: file, line: line)
        XCTAssertEqual(a.tz, b.tz, accuracy: metres, "tz", file: file, line: line)
    }

    func testComposeAndInverse() {
        let a = Placement4(yaw: 0.8, tx: 3, ty: 0.5, tz: -2), b = Placement4(yaw: -2.1, tx: -1, ty: 0.1, tz: 4)
        let p = SIMD3<Float>(1.5, 0.2, -0.7)
        let viaCompose = a.then(b).apply(p), stepwise = a.apply(b.apply(p))
        XCTAssertEqual(simd_distance(viaCompose, stepwise), 0, accuracy: 1e-5)
        XCTAssertEqual(simd_distance(a.inverse.apply(a.apply(p)), p), 0, accuracy: 1e-5)
    }

    func testBetweenRecoversTheTransformFromOneCamera() {
        let truth = Placement4(yaw: 1.1, tx: 4, ty: -0.3, tz: 7)
        // A camera in B facing some direction, pitched a little.
        var poseB = simd_float4x4(simd_quatf(angle: 0.4, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.2, axis: SIMD3(1, 0, 0)))
        poseB.columns.3 = SIMD4(2, 1.4, -3, 1)
        let r = simd_float4x4(simd_quatf(angle: -truth.yaw, axis: SIMD3(0, 1, 0)))   // turning about y by −yaw adds yaw to heading
        var poseA = r * poseB
        let moved = truth.apply(SIMD3(poseB.columns.3.x, poseB.columns.3.y, poseB.columns.3.z))
        poseA.columns.3 = SIMD4(moved, 1)
        assertClose(Placement4.between(poseInA: poseA, poseInB: poseB), truth)
    }

    /// A walk seen by three scans: 10 and 20 overlap, 20 and 30 overlap, 10 and 30 never do.
    func testPlacesScansThroughEachOtherAndIgnoresAnOutlier() {
        let place: [Int: Placement4] = [
            10: Placement4(yaw: 0, tx: 0, ty: 0, tz: 0),
            20: Placement4(yaw: 2.3, tx: 18, ty: -0.5, tz: 47),
            30: Placement4(yaw: -0.9, tx: 30, ty: 0.4, tz: 60),
        ]
        let mapFromSession = Placement4(yaw: 0.6, tx: -5, ty: 1.2, tz: 9)
        var samples: [ScanLinkSolver.Sample] = []
        func add(_ id: Int, _ t: TimeInterval, noise: Float = 0) {
            // scan ← session = (scan ← map) · (map ← session), with a little noise.
            var s = place[id]!.inverse.then(mapFromSession)
            s.tx += noise; s.tz -= noise
            samples.append(.init(mapID: id, time: t, fromSession: s))
        }
        for t in stride(from: 0.0, to: 30, by: 1.5) { add(10, t, noise: Float(t.truncatingRemainder(dividingBy: 3)) * 0.02) }
        for t in stride(from: 20.0, to: 60, by: 1.5) { add(20, t + 0.3) }
        for t in stride(from: 50.0, to: 80, by: 1.5) { add(30, t + 0.6) }
        // One confidently wrong fix from scan 30.
        samples.append(.init(mapID: 30, time: 55.1, fromSession: Placement4(yaw: 2, tx: 90, ty: 0, tz: -40)))

        let links = ScanLinkSolver().solve(samples: samples, reference: 10, referencePlacement: place[10]!)
        XCTAssertEqual(Set(links.keys), [10, 20, 30])
        assertClose(links[20]!.placement, place[20]!, metres: 0.05)
        assertClose(links[30]!.placement, place[30]!, metres: 0.05)
        XCTAssertEqual(links[30]!.via, 20, "30 never overlaps 10, so it is joined through 20")
        XCTAssertLessThan(links[30]!.spreadMetres, 0.1)
    }

    func testNothingIsPlacedWithoutTheReferenceOrEnoughPairs() {
        let s = Placement4.identity
        let onlyOther = [ScanLinkSolver.Sample(mapID: 2, time: 0, fromSession: s)]
        XCTAssertTrue(ScanLinkSolver().solve(samples: onlyOther, reference: 1, referencePlacement: s).isEmpty)
        let fewPairs = [ScanLinkSolver.Sample(mapID: 1, time: 0, fromSession: s), .init(mapID: 2, time: 1, fromSession: s)]
        let links = ScanLinkSolver().solve(samples: fewPairs, reference: 1, referencePlacement: s)
        XCTAssertEqual(Set(links.keys), [1], "one pair is below the minimum of three")
    }

    func testFixesFromDifferentARKitSessionsAreNotPaired() {
        let s = Placement4.identity
        let other = Placement4(yaw: 1, tx: 9, ty: 0, tz: 9)
        var samples: [ScanLinkSolver.Sample] = []
        for t in 0..<5 { samples.append(.init(mapID: 1, time: Double(t), fromSession: s, session: 0)) }
        for t in 0..<5 { samples.append(.init(mapID: 2, time: Double(t) + 0.5, fromSession: other, session: 1)) }
        XCTAssertEqual(Set(ScanLinkSolver().solve(samples: samples, reference: 1, referencePlacement: s).keys), [1])
    }

    func testCircularMedianAcrossPi() {
        let v: [Float] = [3.1, -3.1, 3.05, -3.12, 3.13]
        XCTAssertEqual(abs(ScanLinkSolver.circularMedian(v)), 3.13, accuracy: 0.05)
    }
}
