import Foundation
import simd

/// Decides whether a localization fix is plausible enough to move the visitor.
///
/// Immersal returns no confidence score, and the probe walk showed one fix in
/// twenty-five landing 2.5 m from the truth. Without ARKit odometry to compare
/// against, the only motion reference in a pocket is the pedometer: a person
/// cannot have moved further than they walked, plus some slack for stride
/// estimation and the fix's own error. A fix that jumps further than that is
/// dropped.
///
/// A dropped fix must never lock the visitor out for good — the *previous* fix
/// may have been the wrong one — so after `maxRejections` in a row the next fix
/// is accepted as a fresh anchor.
struct FixGate: Equatable {
    /// Metres a fix may exceed the walked distance by and still be believed.
    var slack: Float = 1.5
    var maxRejections = 3

    struct Anchor: Equatable {
        var position: SIMD2<Float>
        /// Pedometer distance at the moment of acceptance.
        var walked: Float
    }

    private(set) var anchor: Anchor?
    private(set) var consecutiveRejections = 0

    /// Metres the last evaluated fix jumped by, for diagnostics.
    private(set) var lastJump: Float = 0

    /// - Returns: `true` when the fix should be used.
    mutating func evaluate(position: SIMD2<Float>, walked: Float) -> Bool {
        guard let anchor else {
            accept(position: position, walked: walked)
            return true
        }
        lastJump = simd_distance(position, anchor.position)
        let allowed = max(0, walked - anchor.walked) + slack
        if lastJump <= allowed {
            accept(position: position, walked: walked)
            return true
        }
        consecutiveRejections += 1
        if consecutiveRejections >= maxRejections {
            accept(position: position, walked: walked)
            return true
        }
        return false
    }

    mutating func reset() {
        anchor = nil
        consecutiveRejections = 0
        lastJump = 0
    }

    private mutating func accept(position: SIMD2<Float>, walked: Float) {
        anchor = Anchor(position: position, walked: walked)
        consecutiveRejections = 0
    }
}
