import Foundation
import Observation

/// Runs the focal-length sweep described in `FocalCalibration`: grabs a frame,
/// submits it once per candidate, repeats, and keeps score.
///
/// The wearer stands still in a mapped spot for the duration — about a minute
/// for three rounds at Immersal's usual latency.
@MainActor
@Observable
final class FocalCalibrationRunner {

    static let rounds = 3

    enum State: Equatable {
        case idle
        case running(round: Int, candidate: Int)
        case finished(bestFocalPx: Float?)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var samples: [FocalCalibration.Sample] = []
    var scores: [FocalCalibration.Score] { FocalCalibration.rank(samples) }

    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - nextFrame: the latest glasses frame as packed gray pixels, or `nil`
    ///     when none is available.
    ///   - localize: one Immersal localization, on the phone or in the cloud.
    func run(nextFrame: @escaping @MainActor () async -> GrayFrame?,
             localize: @escaping GlassesPositioning.Localize) {
        guard task == nil else { return }
        samples = []
        task = Task { [weak self] in
            defer { self?.task = nil }
            for round in 1...Self.rounds {
                guard let frame = await nextFrame() else {
                    self?.state = .failed("No frame from the glasses. Is the stream running?")
                    return
                }
                for (index, focal) in FocalCalibration.candidates.enumerated() {
                    guard !Task.isCancelled else { self?.state = .idle; return }
                    self?.state = .running(round: round, candidate: index + 1)
                    let camera = GlassesCamera(focalPx: focal)
                    let result = await localize(frame, camera.intrinsics(width: frame.width, height: frame.height))
                    if ImmersalClient.isTransportFailure(result.error) {
                        self?.state = .failed(result.error)
                        return
                    }
                    let position = result.pose.map { SIMD3<Float>($0.px, $0.py, $0.pz) }
                    self?.samples.append(.init(focalPx: focal, success: result.success, position: position))
                }
            }
            guard let self else { return }
            let best = FocalCalibration.best(self.samples)
            if let best { GlassesCamera(focalPx: best).save() }
            self.state = .finished(bestFocalPx: best)
        }
    }

    func cancel() {
        task?.cancel()
    }
}
