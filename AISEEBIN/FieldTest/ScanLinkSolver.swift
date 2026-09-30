import Foundation
import simd

/// A turn about the vertical plus an offset, the only freedom between two
/// gravity-aligned frames (ARKit's session, an Immersal scan, the map). Same
/// convention as `ImmersalAlignment`: x' = c·x − s·z + tx, z' = s·x + c·z + tz.
struct Placement4: Equatable {
    var yaw: Float
    var tx: Float
    var ty: Float
    var tz: Float

    static let identity = Placement4(yaw: 0, tx: 0, ty: 0, tz: 0)

    func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let c = cos(yaw), s = sin(yaw)
        return SIMD3(c * p.x - s * p.z + tx, p.y + ty, s * p.x + c * p.z + tz)
    }

    /// `self ∘ other`: apply `other` first, then `self`.
    func then(_ other: Placement4) -> Placement4 { composed(self, other) }

    var inverse: Placement4 {
        let c = cos(-yaw), s = sin(-yaw)
        return Placement4(yaw: -yaw, tx: -(c * tx - s * tz), ty: -ty, tz: -(s * tx + c * tz))
    }

    /// The transform taking a pose in frame B to the same pose in frame A,
    /// from one camera seen in both: `poseInA = result · poseInB` (up to the turn about y).
    static func between(poseInA: simd_float4x4, poseInB: simd_float4x4) -> Placement4 {
        let yaw = NavigationGeometry.wrapAngle(NavigationGeometry.heading(of: poseInA) - NavigationGeometry.heading(of: poseInB))
        let c = cos(yaw), s = sin(yaw)
        let b = poseInB.columns.3, a = poseInA.columns.3
        return Placement4(yaw: yaw, tx: a.x - (c * b.x - s * b.z), ty: a.y - b.y, tz: a.z - (s * b.x + c * b.z))
    }

    init(yaw: Float, tx: Float, ty: Float, tz: Float) {
        self.yaw = yaw; self.tx = tx; self.ty = ty; self.tz = tz
    }

    init(_ m: ImmersalAlignment.MapPlacement, ty: Float = 0) {
        self.init(yaw: m.yaw, tx: m.tx, ty: ty, tz: m.tz)
    }
}

private func composed(_ a: Placement4, _ b: Placement4) -> Placement4 {
    let c = cos(a.yaw), s = sin(a.yaw)
    return Placement4(yaw: NavigationGeometry.wrapAngle(a.yaw + b.yaw),
                      tx: c * b.tx - s * b.tz + a.tx,
                      ty: a.ty + b.ty,
                      tz: s * b.tx + c * b.tz + a.tz)
}

/// Works out where each Immersal scan sits in the map from one ARKit walk.
///
/// Each fix from scan m on a frame whose ARKit pose is known gives
/// `m ← session` for that moment. Two scans fixed within `pairWindow` seconds
/// of each other are joined through the session: `ref ← m = (ref ← session) ·
/// (m ← session)⁻¹`. Keeping the two fixes close in time keeps ARKit's drift
/// out of the result. Scans are placed outward from the reference, each
/// through the best-connected scan already placed, and every estimate is the
/// median of its pairs, so one wrong fix does not move a scan.
struct ScanLinkSolver {
    struct Sample: Equatable {
        var mapID: Int
        var time: TimeInterval
        /// `scan ← session` at that moment.
        var fromSession: Placement4
        /// ARKit session this was taken in: a restart gives the session a new
        /// origin, so fixes from different sessions are never paired.
        var session: Int = 0
    }

    struct Link: Equatable {
        var mapID: Int
        /// Where the scan sits in the map (`map ← scan`).
        var placement: Placement4
        /// Pairs behind the estimate, and how far they disagreed (median absolute deviation).
        var pairs: Int
        var spreadMetres: Float
        var spreadDegrees: Float
        /// The scan it was joined through; nil for the reference.
        var via: Int?
    }

    var pairWindow: TimeInterval = 15
    var minimumPairs = 3

    /// - Parameters:
    ///   - reference: the scan whose placement is kept as it is.
    ///   - referencePlacement: where the reference sits in the map.
    func solve(samples: [Sample], reference: Int, referencePlacement: Placement4) -> [Int: Link] {
        var placed: [Int: Link] = [:]
        guard samples.contains(where: { $0.mapID == reference }) else { return placed }
        placed[reference] = Link(mapID: reference, placement: referencePlacement, pairs: 0, spreadMetres: 0, spreadDegrees: 0, via: nil)
        let ids = Set(samples.map(\.mapID))
        var progress = true
        while progress {
            progress = false
            var best: Link?
            for m in ids where placed[m] == nil {
                for (p, link) in placed {
                    guard let (rel, n, spreadM, spreadD) = relative(from: m, to: p, samples: samples), n >= minimumPairs else { continue }
                    let candidate = Link(mapID: m, placement: link.placement.then(rel), pairs: n,
                                         spreadMetres: spreadM, spreadDegrees: spreadD, via: p)
                    if best == nil || candidate.pairs > best!.pairs { best = candidate }
                }
            }
            if let best { placed[best.mapID] = best; progress = true }
        }
        return placed
    }

    /// `p ← m` from every pair of close-in-time fixes, with how far the pairs disagreed.
    func relative(from m: Int, to p: Int, samples: [Sample]) -> (Placement4, Int, Float, Float)? {
        let ms = samples.filter { $0.mapID == m }, ps = samples.filter { $0.mapID == p }
        var estimates: [Placement4] = []
        for a in ms {
            // The closest fix of the other scan, if close enough.
            guard let b = ps.filter({ $0.session == a.session }).min(by: { abs($0.time - a.time) < abs($1.time - a.time) }),
                  abs(b.time - a.time) <= pairWindow else { continue }
            estimates.append(b.fromSession.then(a.fromSession.inverse))
        }
        guard !estimates.isEmpty else { return nil }
        let yaw = Self.circularMedian(estimates.map(\.yaw))
        let tx = Self.median(estimates.map(\.tx)), ty = Self.median(estimates.map(\.ty)), tz = Self.median(estimates.map(\.tz))
        let spreadM = Self.median(estimates.map { hypot($0.tx - tx, $0.tz - tz) })
        let spreadD = Self.median(estimates.map { abs(NavigationGeometry.wrapAngle($0.yaw - yaw)) }) * 180 / .pi
        return (Placement4(yaw: yaw, tx: tx, ty: ty, tz: tz), estimates.count, spreadM, spreadD)
    }

    static func median(_ v: [Float]) -> Float {
        let s = v.sorted(); guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Median of angles, taken around their circular mean so ±π does not split them.
    static func circularMedian(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        let mean = atan2(v.map(sin).reduce(0, +), v.map(cos).reduce(0, +))
        return NavigationGeometry.wrapAngle(mean + median(v.map { NavigationGeometry.wrapAngle($0 - mean) }))
    }
}
