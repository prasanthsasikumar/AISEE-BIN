import Foundation
import simd

/// Anchors the ARKit session from position-only fixes (the glasses in lanyard
/// mode) before any full-pose fix has arrived. Each glasses fix pairs where
/// ARKit says the phone is with where Immersal says the head is; once the
/// pairs span enough ground, the yaw and translation fall out of the same 2D
/// Procrustes fit the probe walk uses. The head-to-chest offset is noise here.
struct PositionPairBootstrap: Equatable {
    var minimumPairs = 4
    var minimumSpread: Float = 2
    /// Only the newest pairs count: minutes of standing still must not bury
    /// the walk that finally covers some ground.
    var maxPairs = 12

    struct Pair: Equatable {
        /// ARKit camera position (x, y, z) when the glasses frame was shot.
        var session: SIMD3<Float>
        /// Immersal camera position in the graph frame.
        var graph: SIMD3<Float>
    }

    private(set) var pairs: [Pair] = []

    mutating func add(session: SIMD3<Float>, graph: SIMD3<Float>) {
        pairs.append(Pair(session: session, graph: graph))
        if pairs.count > maxPairs { pairs.removeFirst(pairs.count - maxPairs) }
    }

    mutating func reset() { pairs.removeAll() }

    /// A fit whose residual is worse than this is a mismatch, not a walk.
    var maxRMSError: Float = 1

    /// The fit, or `nil` while too little ground is covered or the pairs do
    /// not agree. The spread is required on the *session* side too: ARKit is
    /// the trustworthy one, and one Immersal mismatch 5 m away must not pass
    /// for a walk by itself.
    func solve() -> ImmersalAnchor.Fit? {
        let planar = pairs.map {
            ImmersalAlignment.Pair(immersal: SIMD2($0.session.x, $0.session.z), graph: SIMD2($0.graph.x, $0.graph.z))
        }
        guard Self.boundingDiagonal(planar.map(\.immersal)) >= minimumSpread else { return nil }
        guard let a = try? ImmersalAlignment.fit(pairs: planar, mapIDs: [],
                                                 minimumPairs: minimumPairs, minimumSpread: minimumSpread),
              a.rmsError <= maxRMSError else { return nil }
        let ty = pairs.reduce(Float(0)) { $0 + ($1.graph.y - $1.session.y) } / Float(pairs.count)
        return ImmersalAnchor.Fit(yaw: a.yaw, tx: a.tx, ty: ty, tz: a.tz)
    }

    private static func boundingDiagonal(_ points: [SIMD2<Float>]) -> Float {
        guard let first = points.first else { return 0 }
        var lo = first, hi = first
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return simd_length(hi - lo)
    }
}
