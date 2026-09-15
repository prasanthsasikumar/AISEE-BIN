import Foundation
import simd

/// Carries the visitor between localization fixes.
///
/// Fixes arrive every second or two at best and can be missing for longer. In
/// between, the pedometer says how far the visitor has walked and the last fix
/// says which way they were facing; walking on along that heading is a far
/// better guess than standing still, and is what keeps "in 3 meters, turn right"
/// counting down smoothly rather than in jumps.
///
/// Heading is the *head* direction at the last fix. People mostly look where
/// they walk, and the guidance loop tolerates a metre or two of error at the
/// approach radius, so no attempt is made to infer body direction separately.
struct PoseExtrapolator: Equatable {
    /// A fix older than this no longer describes where the visitor is.
    var staleAfter: TimeInterval = 8

    struct Fix: Equatable {
        var position: SIMD2<Float>
        var heading: Float
        /// Pedometer distance at the fix.
        var walked: Float
        var time: TimeInterval
    }

    private(set) var fix: Fix?

    mutating func anchor(position: SIMD2<Float>, heading: Float, walked: Float, time: TimeInterval) {
        fix = Fix(position: position, heading: heading, walked: walked, time: time)
    }

    mutating func reset() { fix = nil }

    func isStale(at time: TimeInterval) -> Bool {
        guard let fix else { return true }
        return time - fix.time > staleAfter
    }

    /// Position advanced along the fix heading by the metres walked since.
    func position(walked: Float) -> SIMD2<Float>? {
        guard let fix else { return nil }
        let advance = max(0, walked - fix.walked)
        return fix.position + advance * SIMD2(sin(fix.heading), -cos(fix.heading))
    }

    /// A camera transform in the graph frame, as `NavigationGeometry` reads it:
    /// the camera looks down its own −Z, so `heading(of:)` recovers `fix.heading`.
    func cameraTransform(walked: Float) -> simd_float4x4? {
        guard let fix, let p = position(walked: walked) else { return nil }
        return Self.transform(position: p, heading: fix.heading)
    }

    static func transform(position p: SIMD2<Float>, heading h: Float) -> simd_float4x4 {
        let forward = SIMD3<Float>(sin(h), 0, -cos(h))
        let right = SIMD3<Float>(cos(h), 0, sin(h))
        return simd_float4x4(columns: (
            SIMD4<Float>(right, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-forward, 0),
            SIMD4<Float>(p.x, 0, p.y, 1)
        ))
    }
}
