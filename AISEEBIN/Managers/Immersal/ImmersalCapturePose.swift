import Foundation
import simd

/// The pose an ARKit camera transform becomes when submitted with a mapping
/// photo: the exact inverse of `ImmersalPose.cameraPoseInMap` under the
/// convention confirmed on 2026-09-15, so a map built on these poses answers
/// localizations in ARKit's own session frame.
///
/// ARKit's camera transform is stated for the landscape-right sensor image,
/// which is also the image we send, so no screen-orientation rotation applies.
enum ImmersalCapturePose {
    struct Encoded: Equatable {
        var px: Float, py: Float, pz: Float
        /// r00, r01, r02, r10, … r22: row-major, as `/captureb64` wants them.
        var r: [Float]

        var fields: [String: Any] {
            ["px": px, "py": py, "pz": pz,
             "r00": r[0], "r01": r[1], "r02": r[2],
             "r10": r[3], "r11": r[4], "r12": r[5],
             "r20": r[6], "r21": r[7], "r22": r[8]]
        }
    }

    static func encode(cameraTransform t: simd_float4x4,
                       convention: ImmersalPoseConvention = .provisional) -> Encoded {
        var rotation = simd_float3x3(columns: (
            SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
            SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
            SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        ))
        if convention.flipsCameraAxes {
            // diag(1, -1, -1) is its own inverse: ARKit camera axes back to CV.
            rotation = simd_float3x3(columns: (rotation.columns.0, -rotation.columns.1, -rotation.columns.2))
        }
        if !convention.isRowMajor { rotation = rotation.transpose }
        // r_ij is row i, column j; columns.j[i] is row i of column j.
        let c0 = rotation.columns.0, c1 = rotation.columns.1, c2 = rotation.columns.2
        return Encoded(px: t.columns.3.x, py: t.columns.3.y, pz: t.columns.3.z,
                       r: [c0.x, c1.x, c2.x,
                           c0.y, c1.y, c2.y,
                           c0.z, c1.z, c2.z])
    }
}
