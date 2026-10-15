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
/// Heading is the *head* direction at the last fix plus the body's turn since,
/// from the phone's gyro (`TurnSource`). People mostly look where they walk,
/// so the offset absorbed at the fix is small; the gyro then makes a turn show
/// up in the heading at once instead of at the next fix. Distance still walks
/// along the fix heading.
struct PoseExtrapolator: Equatable {
    /// A fix older than this no longer describes where the visitor is.
    var staleAfter: TimeInterval = 8

    struct Fix: Equatable {
        var position: SIMD2<Float>
        var heading: Float
        /// Pedometer distance at the fix.
        var walked: Float
        /// Gyro turn (`TurnSource.turn`) at the fix.
        var turn: Float
        var time: TimeInterval
    }

    private(set) var fix: Fix?

    mutating func anchor(position: SIMD2<Float>, heading: Float, walked: Float, turn: Float, time: TimeInterval) {
        fix = Fix(position: position, heading: heading, walked: walked, turn: turn, time: time)
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

    /// Fix heading plus the body's turn since the fix.
    func heading(turn: Float) -> Float? {
        guard let fix else { return nil }
        return fix.heading + (turn - fix.turn)
    }

    /// A camera transform in the graph frame, as `NavigationGeometry` reads it:
    /// the camera looks down its own −Z, so `heading(of:)` recovers the heading.
    func cameraTransform(walked: Float, turn: Float) -> simd_float4x4? {
        guard let p = position(walked: walked), let h = heading(turn: turn) else { return nil }
        return Self.transform(position: p, heading: h)
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
