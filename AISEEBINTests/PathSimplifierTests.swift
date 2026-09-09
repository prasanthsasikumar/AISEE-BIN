import XCTest
import simd
@testable import AISEEBIN

final class PathSimplifierTests: XCTestCase {

    func testStraightWalkCollapsesToEndpoints() {
        let trail = (0...10).map { SIMD2<Float>(0, -Float($0)) }
        XCTAssertEqual(PathSimplifier.simplify(trail, tolerance: 0.5), [SIMD2<Float>(0, 0), SIMD2<Float>(0, -10)])
    }

    func testLShapedWalkKeepsTheCorner() {
        var trail = (0...8).map { SIMD2<Float>(0, -Float($0)) }
        trail += (1...6).map { SIMD2<Float>(Float($0), -8) }
        let simplified = PathSimplifier.simplify(trail, tolerance: 0.5)
        XCTAssertEqual(simplified, [SIMD2<Float>(0, 0), SIMD2<Float>(0, -8), SIMD2<Float>(6, -8)])
    }

    func testSmallWobbleWithinToleranceIsIgnored() {
        let trail = [SIMD2<Float>(0, 0), SIMD2<Float>(0.2, -2), SIMD2<Float>(-0.2, -4), SIMD2<Float>(0, -6)]
        XCTAssertEqual(PathSimplifier.simplify(trail, tolerance: 0.5).count, 2)
    }

    func testTinyInputsPassThrough() {
        XCTAssertEqual(PathSimplifier.simplify([], tolerance: 0.5), [])
        XCTAssertEqual(PathSimplifier.simplify([SIMD2<Float>(1, 1)], tolerance: 0.5), [SIMD2<Float>(1, 1)])
    }
}
