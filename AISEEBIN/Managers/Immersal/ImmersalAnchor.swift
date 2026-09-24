import Foundation
import simd

/// Ties ARKit's session frame to the route graph using Immersal fixes.
///
/// ARKit tracks the phone smoothly but starts every session at an arbitrary
/// origin; Immersal says where the camera is in the map but only now and then.
/// Each accepted fix pairs the two poses at one instant and refits the rigid
/// yaw-plus-translation transform between them. Every ARKit frame is then
/// mapped through that transform, so guidance runs on smooth motion and only
/// the *anchor* moves when a fix arrives.
///
/// A fix that would jump the visitor further than `maxJump` from where ARKit
/// says they now are is rejected as a mismatch; three in a row are believed
/// instead, since ARKit itself may have drifted or been reset.
struct ImmersalAnchor: Equatable {
    var maxJump: Float = 1.5
    var maxRejections = 3

    /// Graph-from-session: rotation about Y by `yaw` (the same construction as
    /// `ImmersalAlignment.transform`, so yaw adds to `NavigationGeometry.heading`)
    /// followed by the translation.
    struct Fit: Equatable {
        var yaw: Float
        var tx: Float
        var ty: Float
        var tz: Float

        var transform: simd_float4x4 {
            let c = cos(yaw), s = sin(yaw)
            return simd_float4x4(columns: (
                SIMD4<Float>(c, 0, s, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>(tx, ty, tz, 1)
            ))
        }
    }

    private(set) var fit: Fit?
    private(set) var fixes = 0
    private(set) var rejected = 0
    private(set) var consecutiveRejections = 0
    private(set) var lastJump: Float = 0

    var isAnchored: Bool { fit != nil }

    /// The session pose in the graph frame, or `nil` before the first fix.
    func toGraph(_ sessionPose: simd_float4x4) -> simd_float4x4? {
        fit.map { $0.transform * sessionPose }
    }

    /// Offers a fix: the camera pose Immersal reported, already in the graph
    /// frame, and ARKit's pose for the same frame. Returns whether it was used.
    @discardableResult
    mutating func update(graphPose: simd_float4x4, sessionPose: simd_float4x4) -> Bool {
        let candidate = Self.fit(graphPose: graphPose, sessionPose: sessionPose)
        if let current = fit {
            let predicted = NavigationGeometry.planarPosition(of: current.transform * sessionPose)
            let implied = NavigationGeometry.planarPosition(of: graphPose)
            lastJump = simd_distance(predicted, implied)
            if lastJump > maxJump {
                consecutiveRejections += 1
                rejected += 1
                if consecutiveRejections < maxRejections { return false }
            }
        } else {
            lastJump = 0
        }
        fit = candidate
        fixes += 1
        consecutiveRejections = 0
        return true
    }

    mutating func reset() {
        fit = nil
        fixes = 0
        rejected = 0
        consecutiveRejections = 0
        lastJump = 0
    }

    private static func fit(graphPose: simd_float4x4, sessionPose: simd_float4x4) -> Fit {
        let yaw = NavigationGeometry.wrapAngle(NavigationGeometry.heading(of: graphPose)
                                               - NavigationGeometry.heading(of: sessionPose))
        let c = cos(yaw), s = sin(yaw)
        let sp = sessionPose.columns.3, gp = graphPose.columns.3
        // R · session position, with R as `Fit.transform` applies it.
        let rx = c * sp.x - s * sp.z
        let rz = s * sp.x + c * sp.z
        return Fit(yaw: yaw, tx: gp.x - rx, ty: gp.y - sp.y, tz: gp.z - rz)
    }
}
