import XCTest
import simd
@testable import AISEEBIN

/// The capture pose must be the exact inverse of the localize decode, or a map
/// built on ARKit poses would answer in a frame the graph does not share.
final class ImmersalCapturePoseTests: XCTestCase {
    private func pose(x: Float, y: Float, z: Float, yaw: Float, pitch: Float) -> simd_float4x4 {
        let ry = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)), rx = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
        var m = simd_float4x4(ry * rx); m.columns.3 = SIMD4(x, y, z, 1); return m
    }

    func testRoundTripsThroughTheLocalizeDecode() {
        for (yaw, pitch) in [(0.3 as Float, 0.1 as Float), (-2.0, -0.4), (3.0, 0.9)] {
            let original = pose(x: 1.5, y: -0.8, z: 4.2, yaw: yaw, pitch: pitch)
            let encoded = ImmersalCapturePose.encode(cameraTransform: original)
            let raw = ImmersalRawPose(px: encoded.px, py: encoded.py, pz: encoded.pz, r: encoded.r)
            let decoded = try! XCTUnwrap(ImmersalPose.cameraPoseInMap(raw))
            for c in 0..<4 { for r in 0..<4 {
                XCTAssertEqual(decoded[c][r], original[c][r], accuracy: 1e-5, "column \(c) row \(r) yaw \(yaw)")
            } }
        }
    }

    func testIdentityCameraFlipsOnlyItsOwnYAndZ() {
        let e = ImmersalCapturePose.encode(cameraTransform: matrix_identity_float4x4)
        XCTAssertEqual(e.r, [1, 0, 0, 0, -1, 0, 0, 0, -1])
        XCTAssertEqual(e.fields["r11"] as? Float, -1)
    }
}

final class ScanFramePolicyTests: XCTestCase {
    private func at(x: Float, z: Float, heading: Float = 0) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: heading, axis: SIMD3(0, 1, 0))); m.columns.3 = SIMD4(x, 0, z, 1); return m
    }

    func testCapturesEveryStepOfSpacingWhileWalkingSlowly() {
        var p = ScanFramePolicy()
        var taken = 0
        // 0.05 m per frame at 30 fps = 1.5 m/s… too fast; use 0.015 m per frame = 0.45 m/s
        for i in 0..<400 {
            let t = TimeInterval(i) / 30
            if p.shouldCapture(transform: at(x: Float(i) * 0.015, z: 0), timestamp: t, trackingNormal: true) { taken += 1 }
        }
        // 6 m walked at 0.7 m spacing → first frame plus eight more
        XCTAssertEqual(taken, 9)
        XCTAssertFalse(p.tooFast)
    }

    func testRefusesFramesWhileMovingFast() {
        var p = ScanFramePolicy()
        var taken = 0
        for i in 0..<120 {
            let t = TimeInterval(i) / 30
            if p.shouldCapture(transform: at(x: Float(i) * 0.05, z: 0), timestamp: t, trackingNormal: true) { taken += 1 }
        }
        XCTAssertEqual(taken, 1, "only the very first frame, before speed is known")
        XCTAssertTrue(p.tooFast)
    }

    func testTurningInPlaceAlsoCaptures() {
        var p = ScanFramePolicy()
        var taken = 0
        for i in 0..<300 {
            let t = TimeInterval(i) / 30
            // 0.5 degrees per frame = 15 deg/s
            if p.shouldCapture(transform: at(x: 0, z: 0, heading: Float(i) * 0.5 * .pi / 180), timestamp: t, trackingNormal: true) { taken += 1 }
        }
        // 149.5 degrees of turn at 25 degree steps → captures at 0, 25, 50, 75, 100, 125
        XCTAssertEqual(taken, 6)
    }

    func testNeverCapturesWithoutTrackingOrPastTheCap() {
        var p = ScanFramePolicy(); p.maxImages = 2
        XCTAssertFalse(p.shouldCapture(transform: at(x: 0, z: 0), timestamp: 0, trackingNormal: false))
        XCTAssertTrue(p.shouldCapture(transform: at(x: 0, z: 0), timestamp: 1, trackingNormal: true))
        XCTAssertTrue(p.shouldCapture(transform: at(x: 5, z: 0), timestamp: 20, trackingNormal: true))
        XCTAssertFalse(p.shouldCapture(transform: at(x: 10, z: 0), timestamp: 40, trackingNormal: true))
        XCTAssertTrue(p.isFull)
    }
}
