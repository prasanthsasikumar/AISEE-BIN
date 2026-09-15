import XCTest
import simd
@testable import AISEEBIN

/// The only part of the throwaway Immersal harness worth testing: the pose
/// arithmetic and the CSV schema. Everything the report claims is derived from
/// these, and a silent convention or column-order mistake would not look like a
/// bug — it would look like a finding.
final class ProbeMathTests: XCTestCase {

    /// Asymmetric on purpose: every index is distinguishable, so a transpose or
    /// an off-by-one in the response mapping cannot hide.
    private let raw = ImmersalRawPose(px: 10, py: 20, pz: 30,
                                      r: [1, 2, 3,
                                          4, 5, 6,
                                          7, 8, 9])

    // MARK: - Reading the rotation terms

    func testRowMajorReadsR01AsRowZeroColumnOne() {
        let m = ImmersalPose.cameraPoseInMap(raw, convention: .rowMajorGLCamera)!
        XCTAssertEqual(m.columns.0, SIMD4<Float>(1, 4, 7, 0))
        XCTAssertEqual(m.columns.1, SIMD4<Float>(2, 5, 8, 0))
        XCTAssertEqual(m.columns.2, SIMD4<Float>(3, 6, 9, 0))
    }

    func testColumnMajorTransposesTheRotation() {
        let m = ImmersalPose.cameraPoseInMap(raw, convention: .columnMajorGLCamera)!
        XCTAssertEqual(m.columns.0, SIMD4<Float>(1, 2, 3, 0))
        XCTAssertEqual(m.columns.1, SIMD4<Float>(4, 5, 6, 0))
        XCTAssertEqual(m.columns.2, SIMD4<Float>(7, 8, 9, 0))
    }

    func testPositionAlwaysLandsInTheTranslationColumn() {
        for convention in ImmersalPoseConvention.allCases {
            let m = ImmersalPose.cameraPoseInMap(raw, convention: convention)!
            XCTAssertEqual(m.columns.3, SIMD4<Float>(10, 20, 30, 1), "\(convention)")
        }
    }

    func testCVConventionFlipsOnlyTheYAndZBasisVectors() {
        let m = ImmersalPose.cameraPoseInMap(raw, convention: .rowMajorCVCamera)!
        XCTAssertEqual(m.columns.0, SIMD4<Float>(1, 4, 7, 0))
        XCTAssertEqual(m.columns.1, SIMD4<Float>(-2, -5, -8, 0))
        XCTAssertEqual(m.columns.2, SIMD4<Float>(-3, -6, -9, 0))
    }

    /// Flipping *two* axes keeps the determinant at +1, so a CV-convention pose
    /// is still a proper rotation rather than a mirrored one. If this ever fails,
    /// the flip has been written as a reflection and every reported angle is wrong.
    func testCVFlipPreservesRotationProperness() {
        let yaw = simd_float3x3(simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0)))
        let r = (0..<3).flatMap { row in (0..<3).map { column in yaw[column][row] } }
        let pose = ImmersalPose.cameraPoseInMap(
            ImmersalRawPose(px: 0, py: 0, pz: 0, r: r), convention: .rowMajorCVCamera)!
        let rotation = simd_float3x3(columns: (
            SIMD3(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z),
            SIMD3(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z),
            SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        ))
        XCTAssertEqual(simd_determinant(rotation), 1, accuracy: 0.0001)
    }

    func testMalformedRotationIsRejectedRatherThanGuessed() {
        XCTAssertNil(ImmersalPose.cameraPoseInMap(ImmersalRawPose(px: 0, py: 0, pz: 0, r: [1, 2, 3])))
        XCTAssertNil(ImmersalPose.cameraPoseInMap(
            ImmersalRawPose(px: .nan, py: 0, pz: 0, r: Array(repeating: 0, count: 9))))
    }

    // MARK: - Alignment

    func testMapFromARCarriesTheCameraOntoItsMapPose() {
        let cameraInAR = transform(yaw: 0.4, at: SIMD3(1, 0, -2))
        let cameraInMap = transform(yaw: 2.1, at: SIMD3(-5, 0, 7))
        let mapFromAR = ImmersalPose.mapFromAR(cameraPoseInMap: cameraInMap, cameraPoseInAR: cameraInAR)
        assertClose(mapFromAR * cameraInAR, cameraInMap)
    }

    // MARK: - Odometry cross-check

    func testDisagreementIsZeroWhenBothSystemsAgreeOnDistance() {
        let disagreement = ImmersalPose.odometryDisagreement(
            previousFix: ImmersalRawPose(px: 0, py: 0, pz: 0, r: identityTerms),
            fix: ImmersalRawPose(px: 3, py: 0, pz: 4, r: identityTerms),
            previousAR: transform(yaw: 0, at: SIMD3(0, 0, 0)),
            currentAR: transform(yaw: 0, at: SIMD3(0, 0, -5)))
        XCTAssertEqual(disagreement, 0, accuracy: 0.0001)
    }

    func testDisagreementReportsAJumpWhileStandingStill() {
        let disagreement = ImmersalPose.odometryDisagreement(
            previousFix: ImmersalRawPose(px: 0, py: 0, pz: 0, r: identityTerms),
            fix: ImmersalRawPose(px: 8, py: 0, pz: 0, r: identityTerms),
            previousAR: transform(yaw: 0, at: SIMD3(0, 0, 0)),
            currentAR: transform(yaw: 0, at: SIMD3(0.4, 0, 0)))
        XCTAssertEqual(disagreement, 7.6, accuracy: 0.0001)
    }

    /// The claim that makes this metric usable before the rotation convention is
    /// known: it depends on no shared frame. Re-express the ARKit poses in a
    /// completely different frame and the number must not move.
    func testDisagreementIsInvariantToTheFrameARKitReportsIn() {
        let previousFix = ImmersalRawPose(px: 0, py: 0, pz: 0, r: identityTerms)
        let fix = ImmersalRawPose(px: 2, py: 0, pz: 0, r: identityTerms)
        let previousAR = transform(yaw: 0.3, at: SIMD3(1, 0, 1))
        let currentAR = transform(yaw: 0.9, at: SIMD3(4, 0, 1))
        let arbitraryFrame = transform(yaw: -1.7, at: SIMD3(-30, 2, 11))

        let direct = ImmersalPose.odometryDisagreement(previousFix: previousFix, fix: fix,
                                                       previousAR: previousAR, currentAR: currentAR)
        let reframed = ImmersalPose.odometryDisagreement(previousFix: previousFix, fix: fix,
                                                         previousAR: arbitraryFrame * previousAR,
                                                         currentAR: arbitraryFrame * currentAR)
        XCTAssertEqual(direct, reframed, accuracy: 0.0001)
    }

    // MARK: - Intrinsics

    func testIntrinsicsScaleWithTheDownscaledImage() {
        var k = matrix_identity_float3x3
        k.columns.0.x = 1600   // fx
        k.columns.1.y = 1600   // fy
        k.columns.2.x = 960    // ox
        k.columns.2.y = 720    // oy
        let scaled = ImmersalFrameEncoder.scaledIntrinsics(k, factor: 2)
        XCTAssertEqual(scaled.fx, 800)
        XCTAssertEqual(scaled.fy, 800)
        XCTAssertEqual(scaled.ox, 480)
        XCTAssertEqual(scaled.oy, 360)
    }

    func testIntrinsicsAreUntouchedAtFullResolution() {
        var k = matrix_identity_float3x3
        k.columns.0.x = 1600
        k.columns.2.x = 960
        let scaled = ImmersalFrameEncoder.scaledIntrinsics(k, factor: 1)
        XCTAssertEqual(scaled.fx, 1600)
        XCTAssertEqual(scaled.ox, 960)
    }

    // MARK: - Log schema

    func testEveryRowHasExactlyOneFieldPerColumn() {
        let rows = [
            ProbeLogRow(event: .frame, elapsed: 1, arPosition: SIMD3(1, 2, 3),
                        arOrientation: simd_quatf(angle: 0.2, axis: SIMD3(0, 1, 0)),
                        arTrackingState: "normal", arMappingStatus: "mapped", arFeaturePoints: 1200),
            ProbeLogRow(event: .localize, elapsed: 2, immersalSuccess: true, immersalError: "none",
                        immersalMapID: 4242, immersalPose: raw, immersalLatency: 0.312,
                        immersalRequestBytes: 400_000, odometryDisagreement: 0.12),
            ProbeLogRow(event: .stamp, elapsed: 3, placeID: "orchid", note: "Orchid Display"),
            ProbeLogRow(event: .marker, elapsed: 4, note: "Stepped outside"),
        ]
        for row in rows {
            XCTAssertEqual(ProbeLog.line(for: row).csvFieldCount, ProbeLog.columns.count,
                           "\(row.event.rawValue) row")
        }
    }

    func testUnsetMeasurementsAreEmptyRatherThanZero() {
        let line = ProbeLog.line(for: ProbeLogRow(event: .marker, elapsed: 4, note: "outside"))
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let index = ProbeLog.columns.firstIndex(of: "imm_px")!
        XCTAssertEqual(fields[index], "", "a missing fix must not read as the origin")
    }

    func testErrorStringsWithCommasCannotShiftTheColumns() {
        let row = ProbeLogRow(event: .localize, elapsed: 1, immersalSuccess: false,
                              immersalError: "transport: lost connection, retrying")
        let line = ProbeLog.line(for: row)
        XCTAssertTrue(line.contains("\"transport: lost connection, retrying\""))
        XCTAssertEqual(line.csvFieldCount, ProbeLog.columns.count)
    }

    func testImmersalSpaceSeparatedErrorsStayUnquoted() {
        let row = ProbeLogRow(event: .localize, elapsed: 1, immersalSuccess: false,
                              immersalError: "map count")
        XCTAssertTrue(ProbeLog.line(for: row).contains(",map count,"))
    }

    // MARK: - Config parsing

    func testMapIDsAcceptCommasAndSpaces() {
        XCTAssertEqual("101, 102,103".immersalMapIDs, [101, 102, 103])
        XCTAssertEqual("".immersalMapIDs, [])
        XCTAssertEqual("101, oops".immersalMapIDs, [101])
    }

    // MARK: - Helpers

    private let identityTerms: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

    private func transform(yaw: Float, at position: SIMD3<Float>) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)))
        m.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return m
    }

    private func assertClose(_ a: simd_float4x4, _ b: simd_float4x4, file: StaticString = #filePath, line: UInt = #line) {
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(a[column][row], b[column][row], accuracy: 0.0001,
                               "column \(column) row \(row)", file: file, line: line)
            }
        }
    }
}

private extension String {
    /// Counts CSV fields honouring quoted fields, so a test cannot be fooled by
    /// the very comma-escaping it is checking.
    var csvFieldCount: Int {
        var count = 1
        var inQuotes = false
        for character in self {
            if character == "\"" { inQuotes.toggle() }
            if character == ",", !inQuotes { count += 1 }
        }
        return count
    }
}
