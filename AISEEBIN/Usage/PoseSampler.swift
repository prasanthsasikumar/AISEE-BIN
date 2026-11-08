import Foundation

/// Lets one pose through per `interval`: the per-frame path asks this before
/// building a `pose` event, so a 60 Hz camera costs one comparison per frame.
struct PoseSampler {
    let interval: TimeInterval
    private var last: Date?

    init(interval: TimeInterval = 1) { self.interval = interval }

    mutating func shouldSample(at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }

    mutating func reset() { last = nil }
}
