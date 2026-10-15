import Foundation
import simd

/// The last couple of seconds of ARKit poses, so a glasses fix that arrives
/// after its frame was shot can be paired with where the phone was *then*.
struct PoseHistory: Equatable {
    /// How far back samples are kept.
    var keep: TimeInterval = 2
    /// The nearest sample must be this close in time, or there is no answer.
    var tolerance: TimeInterval = 0.5

    struct Sample: Equatable {
        var time: TimeInterval
        var transform: simd_float4x4
    }

    private(set) var samples: [Sample] = []

    mutating func record(_ transform: simd_float4x4, at time: TimeInterval) {
        samples.append(Sample(time: time, transform: transform))
        let cutoff = time - keep
        if let first = samples.firstIndex(where: { $0.time >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
    }

    mutating func reset() { samples.removeAll() }

    /// The sample nearest `time`, or `nil` when none is within `tolerance`.
    func pose(at time: TimeInterval) -> simd_float4x4? {
        guard let best = samples.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(best.time - time) <= tolerance else { return nil }
        return best.transform
    }
}
