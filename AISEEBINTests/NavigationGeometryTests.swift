import XCTest
import simd
@testable import AISEEBIN

final class NavigationGeometryTests: XCTestCase {

    func testPlanarPositionDropsTheYAxis() {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(1.5, 1.2, -3.0, 1)
        XCTAssertEqual(NavigationGeometry.planarPosition(of: transform), SIMD2<Float>(1.5, -3.0))
    }

    func testHeadingIsZeroWhenFacingNegativeZ() {
        XCTAssertEqual(NavigationGeometry.heading(of: matrix_identity_float4x4), 0, accuracy: 0.0001)
    }

    func testHeadingIsNegativeAfterYawingLeft() {
        // Rotating +90° about +Y turns the ARKit forward vector (-Z) toward -X, i.e. left.
        let yawLeft = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)))
        XCTAssertEqual(NavigationGeometry.heading(of: yawLeft), -.pi / 2, accuracy: 0.0001)
    }

    func testRelativeBearingIsPositiveForTargetOnTheRight() {
        let angle = NavigationGeometry.relativeBearing(from: SIMD2<Float>(0, 0),
                                                       heading: 0,
                                                       to: SIMD2<Float>(1, -1))
        XCTAssertEqual(angle, .pi / 4, accuracy: 0.0001)
    }

    func testRelativeBearingWrapsIntoMinusPiToPi() {
        // Facing +Z (heading = π), target straight ahead along +Z: relative angle must be ~0, not 2π.
        let angle = NavigationGeometry.relativeBearing(from: SIMD2<Float>(0, 0),
                                                       heading: .pi,
                                                       to: SIMD2<Float>(0, 5))
        XCTAssertEqual(angle, 0, accuracy: 0.0001)
    }

    func testDistanceToSegmentMeasuresPerpendicularOffset() {
        let d = NavigationGeometry.distance(from: SIMD2<Float>(1, 5),
                                            toSegment: SIMD2<Float>(0, 0),
                                            SIMD2<Float>(0, 10))
        XCTAssertEqual(d, 1, accuracy: 0.0001)
    }

    func testDistanceToSegmentClampsToEndpoints() {
        let d = NavigationGeometry.distance(from: SIMD2<Float>(0, 13),
                                            toSegment: SIMD2<Float>(0, 0),
                                            SIMD2<Float>(0, 10))
        XCTAssertEqual(d, 3, accuracy: 0.0001)
    }
}
