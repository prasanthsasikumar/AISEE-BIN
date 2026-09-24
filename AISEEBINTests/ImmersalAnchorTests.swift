import XCTest
import simd
@testable import AISEEBIN

/// The phone-in-an-imported-map maths: one Immersal fix pins ARKit's session
/// frame to the graph, later ARKit motion is carried through unchanged, and a
/// wild fix does not teleport the visitor.
final class ImmersalAnchorTests: XCTestCase {

    /// A camera at `position` facing `heading` (0 = -z, clockwise positive).
    private func pose(x: Float, z: Float, heading: Float, y: Float = 0) -> simd_float4x4 {
        let c = cos(heading), s = sin(heading)
        var m = matrix_identity_float4x4
        // forward (-columns.2) must be (sin h, 0, -cos h)
        m.columns.2 = SIMD4(-s, 0, c, 0)
        m.columns.0 = SIMD4(c, 0, s, 0)
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    private func assertPlanar(_ t: simd_float4x4, x: Float, z: Float, heading: Float, line: UInt = #line) {
        let p = NavigationGeometry.planarPosition(of: t)
        XCTAssertEqual(p.x, x, accuracy: 1e-3, line: line)
        XCTAssertEqual(p.y, z, accuracy: 1e-3, line: line)
        XCTAssertEqual(NavigationGeometry.wrapAngle(NavigationGeometry.heading(of: t) - heading), 0, accuracy: 1e-3, line: line)
    }

    func testUnanchoredMapsNothing() {
        let anchor = ImmersalAnchor()
        XCTAssertNil(anchor.toGraph(matrix_identity_float4x4))
        XCTAssertFalse(anchor.isAnchored)
    }

    func testFirstFixReproducesTheGraphPose() {
        var anchor = ImmersalAnchor()
        let session = pose(x: 1, z: 2, heading: 0.3)
        let graph = pose(x: -4, z: 7, heading: 2.0, y: -1)
        XCTAssertTrue(anchor.update(graphPose: graph, sessionPose: session))
        let mapped = try! XCTUnwrap(anchor.toGraph(session))
        assertPlanar(mapped, x: -4, z: 7, heading: 2.0)
        XCTAssertEqual(mapped.columns.3.y, -1, accuracy: 1e-3)
        XCTAssertEqual(anchor.fixes, 1)
    }

    func testLaterMotionIsCarriedRigidly() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 0, z: 0, heading: .pi / 2), sessionPose: pose(x: 0, z: 0, heading: 0))
        // Walk 3 m forward in the session frame (toward -z) while facing 0.
        let later = pose(x: 0, z: -3, heading: 0)
        // Facing +x in the graph, forward 3 m lands at x = 3.
        assertPlanar(try! XCTUnwrap(anchor.toGraph(later)), x: 3, z: 0, heading: .pi / 2)
        // Turning right by 0.4 in the session turns right by 0.4 in the graph.
        assertPlanar(try! XCTUnwrap(anchor.toGraph(pose(x: 0, z: -3, heading: 0.4))), x: 3, z: 0, heading: .pi / 2 + 0.4)
    }

    func testConsistentSecondFixRefinesWithoutRejection() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 10, z: 10, heading: 0), sessionPose: pose(x: 0, z: 0, heading: 0))
        // Walked 2 m; Immersal agrees to within half a metre.
        XCTAssertTrue(anchor.update(graphPose: pose(x: 10.4, z: 8, heading: 0.05), sessionPose: pose(x: 0, z: -2, heading: 0)))
        XCTAssertEqual(anchor.fixes, 2)
        XCTAssertEqual(anchor.rejected, 0)
        XCTAssertEqual(anchor.lastJump, 0.4, accuracy: 1e-3)
        assertPlanar(try! XCTUnwrap(anchor.toGraph(pose(x: 0, z: -2, heading: 0))), x: 10.4, z: 8, heading: 0.05)
    }

    func testWildFixIsRejectedUntilThreeAgree() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 0, z: 0, heading: 0), sessionPose: pose(x: 0, z: 0, heading: 0))
        let wild = pose(x: 8, z: 0, heading: 0), still = pose(x: 0, z: 0, heading: 0)
        XCTAssertFalse(anchor.update(graphPose: wild, sessionPose: still))
        XCTAssertFalse(anchor.update(graphPose: wild, sessionPose: still))
        assertPlanar(try! XCTUnwrap(anchor.toGraph(still)), x: 0, z: 0, heading: 0)   // unchanged so far
        XCTAssertEqual(anchor.rejected, 2)
        XCTAssertTrue(anchor.update(graphPose: wild, sessionPose: still))                // third time: believe it
        assertPlanar(try! XCTUnwrap(anchor.toGraph(still)), x: 8, z: 0, heading: 0)
        XCTAssertEqual(anchor.consecutiveRejections, 0)
    }

    func testResetForgetsEverything() {
        var anchor = ImmersalAnchor()
        anchor.update(graphPose: pose(x: 1, z: 1, heading: 1), sessionPose: pose(x: 0, z: 0, heading: 0))
        anchor.reset()
        XCTAssertFalse(anchor.isAnchored)
        XCTAssertEqual(anchor.fixes, 0)
    }
}
