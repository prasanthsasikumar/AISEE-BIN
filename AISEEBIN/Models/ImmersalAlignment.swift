import Foundation
import simd

/// The rigid transform that takes a point in Immersal map space into the
/// graph's frame (the ARKit world-map frame every `NavigationPOI` is stored in).
///
/// Both frames are gravity-aligned, so the transform is a rotation about the
/// vertical axis plus a translation on the floor plane. It is fitted once, from
/// pairs of poses observed on the same camera frames during a phone walk, and
/// stored in the map JSON so glasses mode can position a visitor on a map that
/// was authored with the phone.
///
/// Conventions match `NavigationGeometry`: a heading `h` is the direction
/// `(sin h, -cos h)` on the `(x, z)` plane, and rotating a point by `yaw` adds
/// `yaw` to its heading.
struct ImmersalAlignment: Codable, Equatable {
    /// The Immersal maps this alignment was fitted against, in the order they
    /// should be offered to the localizer.
    var mapIDs: [Int]
    /// Radians. `heading_graph = heading_immersal + yaw`.
    var yaw: Float
    var tx: Float
    var tz: Float
    /// How many pose pairs the fit used, and how well they agreed, in metres.
    /// Diagnostic only; nothing branches on them.
    var pairCount: Int
    var rmsError: Float

    /// Fewer pairs than this and the fit is a guess, not a measurement.
    static let minimumPairs = 8
    /// Pairs clustered inside this diameter cannot pin the rotation down.
    static let minimumSpread: Float = 3

    // MARK: - Applying

    func toGraph(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let c = cos(yaw), s = sin(yaw)
        return SIMD2(c * p.x - s * p.y + tx,
                     s * p.x + c * p.y + tz)
    }

    func toGraphHeading(_ heading: Float) -> Float {
        NavigationGeometry.wrapAngle(heading + yaw)
    }

    /// The full 4×4, for callers that carry a camera pose rather than a point.
    /// Vertical offset is left at zero: nothing in guidance reads `y`.
    var transform: simd_float4x4 {
        let c = cos(yaw), s = sin(yaw)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, 0, s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-s, 0, c, 0),
            SIMD4<Float>(tx, 0, tz, 1)
        ))
    }

    func toGraph(cameraPose: simd_float4x4) -> simd_float4x4 {
        transform * cameraPose
    }

    // MARK: - Fitting

    struct Pair: Equatable {
        var immersal: SIMD2<Float>
        var graph: SIMD2<Float>
    }

    enum FitError: LocalizedError, Equatable {
        case tooFewPairs(Int)
        case tooLittleSpread(Float)

        var errorDescription: String? {
            switch self {
            case .tooFewPairs(let n):
                return "Only \(n) usable fixes; at least \(ImmersalAlignment.minimumPairs) are needed."
            case .tooLittleSpread(let m):
                return String(format: "Fixes cover only %.1f m; walk at least %.0f m between them.",
                              m, ImmersalAlignment.minimumSpread)
            }
        }
    }

    /// Least-squares rigid fit (rotation + translation, no scale) of the
    /// Immersal points onto the graph points — 2D Procrustes.
    static func fit(pairs: [Pair], mapIDs: [Int]) throws -> ImmersalAlignment {
        guard pairs.count >= minimumPairs else { throw FitError.tooFewPairs(pairs.count) }
        let spread = boundingDiagonal(pairs.map(\.graph))
        guard spread >= minimumSpread else { throw FitError.tooLittleSpread(spread) }

        let n = Float(pairs.count)
        let a0 = pairs.reduce(SIMD2<Float>.zero) { $0 + $1.immersal } / n
        let b0 = pairs.reduce(SIMD2<Float>.zero) { $0 + $1.graph } / n

        // Maximise Σ b·(R a): cos θ Σ(a·b) + sin θ Σ(a_x b_z − a_z b_x).
        var dot: Float = 0, cross: Float = 0
        for pair in pairs {
            let a = pair.immersal - a0, b = pair.graph - b0
            dot += a.x * b.x + a.y * b.y
            cross += a.x * b.y - a.y * b.x
        }
        let yaw = atan2(cross, dot)
        let c = cos(yaw), s = sin(yaw)
        let rotated = SIMD2(c * a0.x - s * a0.y, s * a0.x + c * a0.y)
        let t = b0 - rotated

        var fitted = ImmersalAlignment(mapIDs: mapIDs, yaw: yaw, tx: t.x, tz: t.y,
                                       pairCount: pairs.count, rmsError: 0)
        let sumSquares = pairs.reduce(Float(0)) { $0 + simd_length_squared(fitted.toGraph($1.immersal) - $1.graph) }
        fitted.rmsError = (sumSquares / n).squareRoot()
        return fitted
    }

    private static func boundingDiagonal(_ points: [SIMD2<Float>]) -> Float {
        guard let first = points.first else { return 0 }
        var lo = first, hi = first
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return simd_length(hi - lo)
    }
}
