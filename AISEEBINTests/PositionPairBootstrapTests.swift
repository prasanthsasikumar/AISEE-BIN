import XCTest
import simd
@testable import AISEEBIN

/// Before any full-pose fix, glasses fixes (position only) and ARKit positions
/// at the same moments give the session-to-graph yaw and translation.
final class PositionPairBootstrapTests: XCTestCase {

    private let yaw: Float = 0.7

    /// Where a session point lands in the graph under yaw 0.7, t = (5, -3), 1.4 m higher.
    private func graph(_ s: SIMD3<Float>) -> SIMD3<Float> {
        let c = cos(yaw), si = sin(yaw)
        return SIMD3(c * s.x - si * s.z + 5, s.y + 1.4, si * s.x + c * s.z - 3)
    }

    private let walk: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0.1, -0.5), SIMD3(2, 0, -1.5), SIMD3(2.5, -0.1, -2.5)]

    func testRecoversPlantedTransformFromFourPairs() throws {
        var b = PositionPairBootstrap()
        for s in walk { b.add(session: s, graph: graph(s)) }
        let fit = try XCTUnwrap(b.solve())
        XCTAssertEqual(fit.yaw, yaw, accuracy: 1e-4)
        XCTAssertEqual(fit.tx, 5, accuracy: 1e-3)
        XCTAssertEqual(fit.tz, -3, accuracy: 1e-3)
        XCTAssertEqual(fit.ty, 1.4, accuracy: 1e-4)
        // A later session pose maps where the planted transform says.
        let s = SIMD3<Float>(4, 0.2, -3)
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(s.x, s.y, s.z, 1)
        let mapped = (fit.transform * pose).columns.3
        let expected = graph(s)
        XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-3)
        XCTAssertEqual(mapped.z, expected.z, accuracy: 1e-3)
    }

    func testRefusesThreePairs() {
        var b = PositionPairBootstrap()
        for s in walk.prefix(3) { b.add(session: s, graph: graph(s)) }
        XCTAssertNil(b.solve())
    }

    func testRefusesOneMetreSpread() {
        var b = PositionPairBootstrap()
        for s in [SIMD3<Float>(0, 0, 0), SIMD3(0.3, 0, 0), SIMD3(0.6, 0, -0.2), SIMD3(0.9, 0, -0.3)] {
            b.add(session: s, graph: graph(s))
        }
        XCTAssertNil(b.solve())
    }

    func testResetClearsThePairs() {
        var b = PositionPairBootstrap()
        for s in walk { b.add(session: s, graph: graph(s)) }
        b.reset()
        XCTAssertTrue(b.pairs.isEmpty)
        XCTAssertNil(b.solve())
    }

    // MARK: - Outliers

    func testStandingStillWithOneGraphOutlierDoesNotSolve() {
        // ARKit says the wearer barely moved; one Immersal mismatch 5 m away
        // would give the graph side a 5 m spread and a yaw made of nothing.
        var b = PositionPairBootstrap()
        let still: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(0.1, 0, 0), SIMD3(0.2, 0, -0.1), SIMD3(0.15, 0, -0.05)]
        for (i, s) in still.enumerated() {
            b.add(session: s, graph: i == 2 ? graph(s) + SIMD3(5, 0, 0) : graph(s))
        }
        XCTAssertNil(b.solve())
    }

    func testWalkWithOneGraphOutlierDoesNotSolve() {
        // A real walk, but one fix is 5 m off: the residual gives it away.
        var b = PositionPairBootstrap()
        for (i, s) in walk.enumerated() {
            b.add(session: s, graph: i == 1 ? graph(s) + SIMD3(5, 0, 0) : graph(s))
        }
        XCTAssertNil(b.solve())
    }

    func testKeepsOnlyTheMostRecentPairs() {
        var b = PositionPairBootstrap()
        for i in 0..<20 {
            let s = SIMD3<Float>(Float(i) * 0.5, 0, 0)
            b.add(session: s, graph: graph(s))
        }
        XCTAssertEqual(b.pairs.count, b.maxPairs)
        XCTAssertEqual(b.pairs.first?.session.x, Float(20 - b.maxPairs) * 0.5, "the oldest pairs are dropped")
        XCTAssertNotNil(b.solve())
    }
}
