import Foundation
import simd

/// The nine rotation terms and three position terms exactly as `/localizeb64`
/// returned them, before any interpretation.
///
/// Kept raw on purpose. The convention Immersal's REST rotation follows is not
/// stated in its documentation, so every logged row carries the original twelve
/// numbers and the interpretation happens in post-processing, where all four
/// candidate conventions can be tried against the data. See
/// `ImmersalPoseConvention`.
struct ImmersalRawPose: Equatable, Sendable {
    /// Position in map space, metres.
    var px: Float
    var py: Float
    var pz: Float
    /// `r00 … r22`, in the order the REST response lists them.
    var r: [Float]

    var isWellFormed: Bool { r.count == 9 && r.allSatisfy(\.isFinite) && [px, py, pz].allSatisfy(\.isFinite) }
}

/// How to read `ImmersalRawPose` into a 4×4 camera-pose-in-map-space matrix.
///
/// Two independent unknowns, hence four combinations:
///
/// - **Index order.** Is `r01` row 0 column 1, or column 0 row 1? Immersal's
///   Unity SDK assigns `r01` to `Matrix4x4.m01`, i.e. row-major, which is why
///   `.rowMajor…` is the default guess — but it is a guess.
/// - **Camera axes.** Computer-vision solvers conventionally put +Y down and +Z
///   forward; ARKit puts +Y up and −Z forward. Converting between them flips the
///   camera's own Y and Z basis vectors. Immersal's native iOS sample applies
///   exactly that flip to the pose its plugin returns, so the REST result very
///   likely needs it too.
///
/// A wrong index order or a wrong flip is a *reflection*, which the rigid
/// best-fit alignment used in analysis cannot absorb — so it shows up as a large
/// irreducible residual rather than hiding. That is precisely how the analysis
/// script identifies the right one.
enum ImmersalPoseConvention: String, CaseIterable {
    case rowMajorCVCamera
    case rowMajorGLCamera
    case columnMajorCVCamera
    case columnMajorGLCamera

    /// Confirmed against a real Immersal map on 2026-09-15: over a 101 s walk,
    /// this reading put the camera's forward vector along the direction of
    /// travel with a median cosine of **+0.97**, against +0.84 for column-major
    /// and −0.97 / −0.84 for the unflipped readings. The same walk showed a
    /// median odometry disagreement of 0.02 m, which also confirms that
    /// `px/py/pz` is the camera's position in map space rather than a view
    /// matrix's translation.
    ///
    /// Still only used for the live on-screen readout; reported numbers come
    /// from the analysis script, which re-derives this from the logged terms.
    static let provisional: ImmersalPoseConvention = .rowMajorCVCamera

    var isRowMajor: Bool { self == .rowMajorCVCamera || self == .rowMajorGLCamera }
    var flipsCameraAxes: Bool { self == .rowMajorCVCamera || self == .columnMajorCVCamera }
}

enum ImmersalPose {

    /// Pose of the camera in Immersal map space, under `convention`.
    static func cameraPoseInMap(_ raw: ImmersalRawPose,
                                convention: ImmersalPoseConvention = .provisional) -> simd_float4x4? {
        guard raw.isWellFormed else { return nil }
        let r = raw.r

        // columns.i.j is column i, row j.
        var rotation = simd_float3x3(columns: (
            SIMD3<Float>(r[0], r[3], r[6]),
            SIMD3<Float>(r[1], r[4], r[7]),
            SIMD3<Float>(r[2], r[5], r[8])
        ))
        if !convention.isRowMajor { rotation = rotation.transpose }

        if convention.flipsCameraAxes {
            // Right-multiply by diag(1, -1, -1): flip the camera's own Y and Z
            // basis vectors, turning a CV camera frame into an ARKit one.
            rotation = simd_float3x3(columns: (
                rotation.columns.0,
                -rotation.columns.1,
                -rotation.columns.2
            ))
        }

        let c0 = rotation.columns.0, c1 = rotation.columns.1, c2 = rotation.columns.2
        return simd_float4x4(columns: (
            SIMD4<Float>(c0.x, c0.y, c0.z, 0),
            SIMD4<Float>(c1.x, c1.y, c1.z, 0),
            SIMD4<Float>(c2.x, c2.y, c2.z, 0),
            SIMD4<Float>(raw.px, raw.py, raw.pz, 1)
        ))
    }

    /// The rigid transform taking a point in the ARKit session frame to Immersal
    /// map space, given both poses of the same camera at the same instant.
    ///
    /// `p_map = cameraPoseInMap · cameraPoseInAR⁻¹ · p_ar`
    static func mapFromAR(cameraPoseInMap: simd_float4x4,
                          cameraPoseInAR: simd_float4x4) -> simd_float4x4 {
        cameraPoseInMap * cameraPoseInAR.inverse
    }

    /// Metres travelled between two poses, ignoring rotation.
    static func displacement(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        simd_distance(SIMD3(a.columns.3.x, a.columns.3.y, a.columns.3.z),
                      SIMD3(b.columns.3.x, b.columns.3.y, b.columns.3.z))
    }

    /// How far Immersal's reported motion between two consecutive fixes differs
    /// from the motion ARKit's odometry measured over the same interval, in metres.
    ///
    /// Deliberately **convention-free**: it compares two scalar distances, and a
    /// distance is invariant to the unknown rigid transform between the two
    /// frames and to any camera-axis flip (which touches rotation only). So this
    /// number is trustworthy even while the rotation convention is still unknown.
    ///
    /// Near zero means the two systems agree you moved the same amount. A large
    /// value with small ARKit motion is the signature of a confidently wrong fix
    /// — the perceptual-aliasing failure that matters most for a blind user,
    /// and the closest thing available to the confidence score the REST API
    /// does not return.
    static func odometryDisagreement(previousFix: ImmersalRawPose, fix: ImmersalRawPose,
                                     previousAR: simd_float4x4, currentAR: simd_float4x4) -> Float {
        let immersal = simd_distance(SIMD3<Float>(previousFix.px, previousFix.py, previousFix.pz),
                                     SIMD3<Float>(fix.px, fix.py, fix.pz))
        return abs(immersal - displacement(previousAR, currentAR))
    }
}
