import Foundation
import simd

/// Pure geometry helpers that translate ARKit camera transforms into the 2D
/// floor-plan frame used by `PathfindingEngine`.
///
/// Conventions (all ARKit-native):
/// - World `x` is right, `y` is up, `-z` is forward from the session origin.
/// - Planar positions are `(x, z)`.
/// - Heading is the yaw of the camera's forward vector, 0 when facing `-z`,
///   positive when rotated clockwise (toward `+x`) seen from above.
enum NavigationGeometry {

    /// Drops the height component of a camera transform.
    static func planarPosition(of transform: simd_float4x4) -> SIMD2<Float> {
        SIMD2(transform.columns.3.x, transform.columns.3.z)
    }

    /// Yaw of the camera in radians, per the conventions above.
    ///
    /// The camera's forward direction is `-columns.2` (ARKit cameras look down
    /// their local -Z axis). We project it onto the floor so a chest mount
    /// tilted up or down still yields a sensible heading.
    static func heading(of transform: simd_float4x4) -> Float {
        let forward = -transform.columns.2
        return atan2(forward.x, -forward.z)
    }

    /// Signed angle the user must turn to face `target`, wrapped to (-π, π].
    /// Positive means turn right.
    static func relativeBearing(from position: SIMD2<Float>, heading: Float, to target: SIMD2<Float>) -> Float {
        let delta = target - position
        let bearing = atan2(delta.x, -delta.y) // delta.y is the z axis
        return wrapAngle(bearing - heading)
    }

    static func distance(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
        simd_distance(a, b)
    }

    /// Shortest distance from `point` to the line segment `a`–`b`.
    static func distance(from point: SIMD2<Float>, toSegment a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > .ulpOfOne else { return simd_distance(point, a) }
        let t = simd_clamp(simd_dot(point - a, ab) / lengthSquared, 0, 1)
        return simd_distance(point, a + ab * t)
    }

    /// Normalises any angle into (-π, π].
    static func wrapAngle(_ angle: Float) -> Float {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }
}
