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

    struct Pair: Equatable {
        /// ARKit camera position (x, y, z) when the glasses frame was shot.
        var session: SIMD3<Float>
        /// Immersal camera position in the graph frame.
        var graph: SIMD3<Float>
    }

    private(set) var pairs: [Pair] = []

    mutating func add(session: SIMD3<Float>, graph: SIMD3<Float>) {
        pairs.append(Pair(session: session, graph: graph))
    }

    mutating func reset() { pairs.removeAll() }

    /// The fit, or `nil` while too little ground is covered.
    func solve() -> ImmersalAnchor.Fit? {
        let planar = pairs.map {
            ImmersalAlignment.Pair(immersal: SIMD2($0.session.x, $0.session.z), graph: SIMD2($0.graph.x, $0.graph.z))
        }
        guard let a = try? ImmersalAlignment.fit(pairs: planar, mapIDs: [],
                                                 minimumPairs: minimumPairs, minimumSpread: minimumSpread) else { return nil }
        let ty = pairs.reduce(Float(0)) { $0 + ($1.graph.y - $1.session.y) } / Float(pairs.count)
        return ImmersalAnchor.Fit(yaw: a.yaw, tx: a.tx, ty: ty, tz: a.tz)
    }
}
