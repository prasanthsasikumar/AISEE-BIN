import Foundation
import simd

/// Decides which ARKit frames become Immersal mapping photos during an Author
/// walk: one every `spacing` metres or `turn` radians, only while the phone is
/// moving slowly enough for a sharp frame, and never more than `maxImages`.
struct ScanFramePolicy {
    var spacing: Float = 0.7
    var turn: Float = 25 * .pi / 180
    var maxLinearSpeed: Float = 0.6        // m/s
    var maxAngularSpeed: Float = 45 * .pi / 180
    var minimumInterval: TimeInterval = 0.4
    var maxImages = 150

    private(set) var captured = 0
    private var lastCapture: (position: SIMD3<Float>, heading: Float, time: TimeInterval)?
    /// Recent samples, newest last, kept for `window` seconds: speed is measured
    /// against the oldest one so a single noisy frame pair cannot decide it.
    private var recent: [(position: SIMD3<Float>, heading: Float, time: TimeInterval)] = []
    private let window: TimeInterval = 0.4
    private let minimumSpan: TimeInterval = 0.15
    private(set) var tooFast = false

    var isFull: Bool { captured >= maxImages }

    /// Feed every frame; returns true for the ones to send.
    mutating func shouldCapture(transform: simd_float4x4, timestamp: TimeInterval, trackingNormal: Bool) -> Bool {
        let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let heading = NavigationGeometry.heading(of: transform)
        recent.removeAll { timestamp - $0.time > window }
        defer { recent.append((position, heading, timestamp)) }
        guard trackingNormal, !isFull else { return false }
        if let oldest = recent.first {
            let span = timestamp - oldest.time
            // Not enough history yet to know the speed: wait rather than guess.
            guard span >= minimumSpan else { return false }
            let dt = Float(span)
            let linear = simd_distance(position, oldest.position) / dt
            let angular = abs(NavigationGeometry.wrapAngle(heading - oldest.heading)) / dt
            tooFast = linear > maxLinearSpeed || angular > maxAngularSpeed
            if tooFast { return false }
        }
        if let last = lastCapture {
            guard timestamp - last.time >= minimumInterval else { return false }
            let moved = simd_distance(position, last.position)
            let turned = abs(NavigationGeometry.wrapAngle(heading - last.heading))
            guard moved >= spacing || turned >= turn else { return false }
        }
        lastCapture = (position, heading, timestamp)
        captured += 1
        return true
    }

    mutating func reset() {
        captured = 0; lastCapture = nil; recent.removeAll(); tooFast = false
    }
}
