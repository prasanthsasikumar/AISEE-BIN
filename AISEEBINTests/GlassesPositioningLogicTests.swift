import XCTest
import simd
@testable import AISEEBIN

/// The pure pieces between an Immersal fix and a `PoseSnapshot`: the gate that
/// drops implausible fixes, the extrapolator that walks the visitor on between
/// fixes, the camera model, and the focal-length scoring.
final class GlassesPositioningLogicTests: XCTestCase {

    // MARK: - FixGate

    func testFirstFixIsAlwaysAccepted() {
        var gate = FixGate()
        XCTAssertTrue(gate.evaluate(position: SIMD2(40, -12), walked: 0))
        XCTAssertEqual(gate.anchor?.position, SIMD2(40, -12))
    }

    func testFixWithinWalkedDistancePlusSlackIsAccepted() {
        var gate = FixGate(slack: 1.5)
        _ = gate.evaluate(position: .zero, walked: 0)
        // Walked 3 m, fix says 4 m: within 1.5 m slack.
        XCTAssertTrue(gate.evaluate(position: SIMD2(4, 0), walked: 3))
        XCTAssertEqual(gate.consecutiveRejections, 0)
    }

    func testTeleportWhileStandingStillIsRejected() {
        var gate = FixGate(slack: 1.5)
        _ = gate.evaluate(position: .zero, walked: 0)
        XCTAssertFalse(gate.evaluate(position: SIMD2(0, 8), walked: 0.2))
        XCTAssertEqual(gate.consecutiveRejections, 1)
        XCTAssertEqual(gate.anchor?.position, .zero, "a rejected fix must not move the anchor")
        XCTAssertEqual(gate.lastJump, 8, accuracy: 1e-5)
    }

    func testRepeatedRejectionsReanchor() {
        var gate = FixGate(slack: 1.5, maxRejections: 3)
        _ = gate.evaluate(position: .zero, walked: 0)
        XCTAssertFalse(gate.evaluate(position: SIMD2(10, 0), walked: 0))
        XCTAssertFalse(gate.evaluate(position: SIMD2(10, 0), walked: 0))
        XCTAssertTrue(gate.evaluate(position: SIMD2(10, 0), walked: 0), "third rejection becomes a fresh anchor")
        XCTAssertEqual(gate.anchor?.position, SIMD2(10, 0))
        XCTAssertEqual(gate.consecutiveRejections, 0)
    }

    func testPedometerResetDoesNotGoNegative() {
        var gate = FixGate(slack: 1.5)
        _ = gate.evaluate(position: .zero, walked: 50)
        // Pedometer restarted at 0; allowed distance is just the slack.
        XCTAssertTrue(gate.evaluate(position: SIMD2(1, 0), walked: 0))
        XCTAssertFalse(gate.evaluate(position: SIMD2(5, 0), walked: 0))
    }

    // MARK: - PoseExtrapolator

    func testAdvancesAlongHeadingByDistanceWalked() {
        var ex = PoseExtrapolator()
        ex.anchor(position: SIMD2(1, 1), heading: .pi / 2, walked: 10, time: 0)   // facing +x
        let p = ex.position(walked: 13)!
        XCTAssertEqual(p.x, 4, accuracy: 1e-5)
        XCTAssertEqual(p.y, 1, accuracy: 1e-5)
    }

    func testDoesNotWalkBackwards() {
        var ex = PoseExtrapolator()
        ex.anchor(position: .zero, heading: 0, walked: 10, time: 0)
        XCTAssertEqual(ex.position(walked: 8)!, .zero)
    }

    func testStaleness() {
        var ex = PoseExtrapolator(staleAfter: 8)
        XCTAssertTrue(ex.isStale(at: 0))
        ex.anchor(position: .zero, heading: 0, walked: 0, time: 100)
        XCTAssertFalse(ex.isStale(at: 107))
        XCTAssertTrue(ex.isStale(at: 108.5))
    }

    func testTransformRoundTripsThroughNavigationGeometry() {
        var ex = PoseExtrapolator()
        ex.anchor(position: SIMD2(-3, 7), heading: 2.2, walked: 0, time: 0)
        let t = ex.cameraTransform(walked: 1.5)!
        XCTAssertEqual(NavigationGeometry.heading(of: t), 2.2, accuracy: 1e-5)
        let p = NavigationGeometry.planarPosition(of: t)
        let expected = SIMD2<Float>(-3, 7) + 1.5 * SIMD2(sin(2.2), -cos(2.2))
        XCTAssertEqual(p.x, expected.x, accuracy: 1e-5)
        XCTAssertEqual(p.y, expected.y, accuracy: 1e-5)
        // A proper rotation, not a reflection.
        let r = simd_float3x3(columns: (SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                                        SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                                        SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)))
        XCTAssertEqual(r.determinant, 1, accuracy: 1e-5)
    }

    // MARK: - GlassesCamera

    func testIntrinsicsScaleWithFrameWidth() {
        let camera = GlassesCamera(focalPx: 900)
        let full = camera.intrinsics(width: 1280, height: 720)
        XCTAssertEqual(full.fx, 900); XCTAssertEqual(full.fy, 900)
        XCTAssertEqual(full.ox, 640); XCTAssertEqual(full.oy, 360)
        let half = camera.intrinsics(width: 640, height: 360)
        XCTAssertEqual(half.fx, 450); XCTAssertEqual(half.ox, 320); XCTAssertEqual(half.oy, 180)
    }

    func testDefaultFOVIsPlausibleForAWearable() {
        let fov = GlassesCamera().horizontalFOVDegrees
        XCTAssertGreaterThan(fov, 60)
        XCTAssertLessThan(fov, 80)
    }

    func testCameraPersistsFocal() {
        let defaults = UserDefaults(suiteName: "GlassesCameraTests")!
        defaults.removePersistentDomain(forName: "GlassesCameraTests")
        XCTAssertEqual(GlassesCamera.load(from: defaults).focalPx, GlassesCamera.defaultFocalPx)
        GlassesCamera(focalPx: 1050).save(to: defaults)
        XCTAssertEqual(GlassesCamera.load(from: defaults).focalPx, 1050)
    }

    // MARK: - FocalCalibration

    private func sample(_ focal: Float, _ ok: Bool, _ p: SIMD3<Float>? = nil) -> FocalCalibration.Sample {
        .init(focalPx: focal, success: ok, position: ok ? (p ?? SIMD3(1, 1, 1)) : nil)
    }

    func testMostSuccessesWins() {
        let samples = [
            sample(800, false), sample(800, true), sample(800, false),
            sample(900, true), sample(900, true), sample(900, true),
            sample(1000, true), sample(1000, false), sample(1000, true),
        ]
        XCTAssertEqual(FocalCalibration.best(samples), 900)
        XCTAssertEqual(FocalCalibration.rank(samples).map(\.focalPx), [900, 1000, 800])
    }

    func testTightestClusterBreaksTies() {
        let samples = [
            sample(800, true, SIMD3(0, 0, 0)), sample(800, true, SIMD3(2, 0, 0)),
            sample(900, true, SIMD3(0, 0, 0)), sample(900, true, SIMD3(0.1, 0, 0)),
        ]
        XCTAssertEqual(FocalCalibration.best(samples), 900)
        let scores = FocalCalibration.rank(samples)
        XCTAssertEqual(scores[0].spread, 0.05, accuracy: 1e-5)
        XCTAssertEqual(scores[1].spread, 1, accuracy: 1e-5)
    }

    func testNothingLocalizedMeansNoAnswer() {
        XCTAssertNil(FocalCalibration.best([sample(800, false), sample(900, false)]))
        XCTAssertNil(FocalCalibration.best([]))
    }

    func testCandidatesBracketAnyWearableCamera() {
        XCTAssertEqual(FocalCalibration.candidates.first, 600)
        XCTAssertEqual(FocalCalibration.candidates.last, 1400)
        XCTAssertTrue(FocalCalibration.candidates.contains(GlassesCamera.defaultFocalPx))
    }
}
