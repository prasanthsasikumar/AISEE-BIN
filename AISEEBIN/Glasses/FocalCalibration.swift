import Foundation
import simd

/// Finds the glasses' focal length by asking the map.
///
/// There is no checkerboard in a greenhouse, but there is a localizer that
/// either recognises an image or does not, and the more wrong the assumed focal
/// length, the fewer frames it recognises. Standing still in a mapped spot, the
/// same frame is submitted once per candidate focal length; over a few frames
/// the candidate with the most successes wins. Ties break on how tightly the
/// returned positions cluster — a wrong focal length that still "succeeds"
/// tends to scatter, because every fix is a slightly different compromise.
///
/// The scoring is pure so it can be tested; `FocalCalibrationRunner` does the
/// network round trips.
enum FocalCalibration {

    /// Pixels at `GlassesCamera.referenceWidth`. 600 is ~94° horizontal,
    /// 1400 is ~49°: wider and narrower than any wearable camera is likely to be.
    static let candidates: [Float] = stride(from: 600, through: 1400, by: 100).map(Float.init)

    struct Sample: Equatable {
        var focalPx: Float
        var success: Bool
        var position: SIMD3<Float>?
    }

    struct Score: Equatable {
        var focalPx: Float
        var successes: Int
        var attempts: Int
        /// RMS distance of the successful positions from their centroid, metres.
        var spread: Float
    }

    /// Best first. Candidates with no samples are omitted.
    static func rank(_ samples: [Sample]) -> [Score] {
        let byFocal = Dictionary(grouping: samples, by: \.focalPx)
        return byFocal.map { focal, group in
            let positions = group.compactMap { $0.success ? $0.position : nil }
            return Score(focalPx: focal, successes: positions.count,
                         attempts: group.count, spread: spread(of: positions))
        }
        .sorted { lhs, rhs in
            if lhs.successes != rhs.successes { return lhs.successes > rhs.successes }
            if lhs.spread != rhs.spread { return lhs.spread < rhs.spread }
            return lhs.focalPx < rhs.focalPx
        }
    }

    /// The winning focal length, or `nil` when nothing localized at all — in
    /// which case the map, not the lens, is the problem.
    static func best(_ samples: [Sample]) -> Float? {
        guard let top = rank(samples).first, top.successes > 0 else { return nil }
        return top.focalPx
    }

    static func spread(of positions: [SIMD3<Float>]) -> Float {
        guard positions.count >= 2 else { return 0 }
        let centroid = positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)
        let sum = positions.reduce(Float(0)) { $0 + simd_length_squared($1 - centroid) }
        return (sum / Float(positions.count)).squareRoot()
    }
}
