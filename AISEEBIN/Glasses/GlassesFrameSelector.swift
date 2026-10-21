import Foundation

/// Which glasses frames are worth an Immersal request.
///
/// Replaying a 224 s glasses clip along the GBTB route (2026-10-17) matched
/// only 15 of 1122 frames, all while the wearer stood still. The blurriest
/// quarter of frames never matched, and frames that did match were about three
/// times sharper than those that did not. The stream spends its bits on one
/// IDR frame a second, and P-frames carry 1–2 KB each. Both filters below are
/// field experiments. `maxWait` stops a filter from starving positioning
/// altogether.
enum GlassesFrameFilter: String, CaseIterable, Sendable {
    /// Every frame, as before.
    case all
    /// Frames whose `FrameSharpness` reaches `GlassesFrameSelector.minSharpness`.
    case sharp
    /// IDR frames only.
    case keyframes

    var label: String {
        switch self {
        case .all: "All frames"
        case .sharp: "Sharp only"
        case .keyframes: "Keyframes only"
        }
    }

    private static let key = "glasses.frameFilter"

    static func load(from defaults: UserDefaults = .standard) -> GlassesFrameFilter {
        defaults.string(forKey: key).flatMap(GlassesFrameFilter.init(rawValue:)) ?? .sharp
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}

enum FrameSharpness {
    /// Variance of the 4-neighbour Laplacian, sampled every 4th pixel in both
    /// directions. The same measure as the clip analysis, so its thresholds
    /// carry over at 960 px wide: frames that matched had a median of 168,
    /// frames that missed a median of 60, and nothing under 26 matched.
    static func score(_ frame: GrayFrame) -> Float {
        let w = frame.width, h = frame.height
        guard w > 4, h > 4 else { return 0 }
        return frame.pixels.withUnsafeBytes { raw -> Float in
            let p = raw.bindMemory(to: UInt8.self)
            var sum: Double = 0, sumSq: Double = 0, n: Double = 0
            var y = 2
            while y < h - 2 {
                let row = y * w
                var x = 2
                while x < w - 2 {
                    let i = row + x
                    let l = 4 * Int(p[i]) - Int(p[i - 1]) - Int(p[i + 1]) - Int(p[i - w]) - Int(p[i + w])
                    sum += Double(l); sumSq += Double(l * l); n += 1
                    x += 4
                }
                y += 4
            }
            guard n > 0 else { return 0 }
            let mean = sum / n
            return Float(sumSq / n - mean * mean)
        }
    }
}

/// The filter's state for one positioning session. Thread-safe: the keyframe
/// check runs on the decode thread, the sharpness check on a worker.
final class GlassesFrameSelector: @unchecked Sendable {
    static let minSharpness: Float = 60
    /// After this long without sending a frame, the next one goes regardless.
    static let maxWait: TimeInterval = 2

    private let lock = NSLock()
    private var filter: GlassesFrameFilter = .all
    private var lastSentAt: TimeInterval = -.infinity
    private var _skippedBlurry = 0
    private var _skippedNonKey = 0

    var skippedBlurry: Int { lock.withLock { _skippedBlurry } }
    var skippedNonKey: Int { lock.withLock { _skippedNonKey } }
    var currentFilter: GlassesFrameFilter { lock.withLock { filter } }

    func reset(filter: GlassesFrameFilter, now: TimeInterval) {
        lock.withLock {
            self.filter = filter
            lastSentAt = now
            _skippedBlurry = 0
            _skippedNonKey = 0
        }
    }

    func set(filter: GlassesFrameFilter) {
        lock.withLock { self.filter = filter }
    }

    /// Decode thread, before any pixels are copied.
    func admits(isKeyframe: Bool, now: TimeInterval) -> Bool {
        lock.withLock {
            guard filter == .keyframes, !isKeyframe, now - lastSentAt < Self.maxWait else { return true }
            _skippedNonKey += 1
            return false
        }
    }

    /// Worker thread, once the frame is gray. Records a send when it admits.
    func admits(sharpness: Float, now: TimeInterval) -> Bool {
        lock.withLock {
            if filter == .sharp, sharpness < Self.minSharpness, now - lastSentAt < Self.maxWait {
                _skippedBlurry += 1
                return false
            }
            lastSentAt = now
            return true
        }
    }
}
