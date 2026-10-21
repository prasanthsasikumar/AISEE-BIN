import Foundation
import Observation
import OSLog
import simd

/// The glasses camera as a source of Immersal fixes for lanyard mode. A frame
/// goes to the localizer the way `GlassesPositioning` sends it (same cadence,
/// width and lens model) and a fix comes back as a camera pose in the graph
/// frame, with the time the frame arrived. No pedometer, no extrapolation, no
/// snapshots: ARKit on the phone is the tracker, and
/// `PhoneImmersalLocalizer.offer` folds each fix into its anchor.
@MainActor
@Observable
final class GlassesFixFeed {
    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "glasses-fix")

    private(set) var attempts = 0
    private(set) var fixes = 0
    private(set) var lastError: String?
    private(set) var lastLatencyMS: Int?
    private(set) var lastMapID: Int?
    /// "on device" or "cloud" for this session.
    private(set) var localizerName = ""
    private(set) var running = false
    private(set) var skippedFrames = 0

    /// A fix: camera pose in the graph frame, and when the frame arrived
    /// (`ProcessInfo.systemUptime`, the same clock as ARKit's frame timestamps).
    @ObservationIgnored var onFix: ((simd_float4x4, TimeInterval) -> Void)?

    var camera = GlassesCamera.load()

    @ObservationIgnored private var alignment: ImmersalAlignment?
    @ObservationIgnored private var localizer: (any ImmersalLocalizer)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let claim = FrameClaim()
    @ObservationIgnored private let selector = GlassesFrameSelector()

    /// Touched on the SDK thread: whether a frame may be claimed right now.
    private final class FrameClaim: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        private var lastClaimAt: TimeInterval = -.infinity
        private var generation = 0

        func arm(generation: Int) {
            lock.withLock { self.generation = generation; claimed = false; lastClaimAt = -.infinity }
        }

        func disarm() { lock.withLock { generation = 0; claimed = false } }

        func tryClaim(now: TimeInterval, minimumInterval: TimeInterval) -> Int? {
            lock.withLock {
                guard generation > 0, !claimed, now - lastClaimAt >= minimumInterval else { return nil }
                claimed = true
                lastClaimAt = now
                return generation
            }
        }

        func release() { lock.withLock { claimed = false } }

        /// Releases a frame the selector turned down, so another can be tried
        /// in `retryAfter` rather than a full `minimumInterval` later.
        func releaseForRetry(minimumInterval: TimeInterval, retryAfter: TimeInterval = 0.1) {
            lock.withLock {
                claimed = false
                lastClaimAt -= max(0, minimumInterval - retryAfter)
            }
        }
    }

    func start(alignment: ImmersalAlignment?) {
        stop()
        self.alignment = alignment
        generation += 1
        attempts = 0; fixes = 0; skippedFrames = 0
        selector.reset(filter: GlassesFrameFilter.load(), now: ProcessInfo.processInfo.systemUptime)
        lastError = nil; lastLatencyMS = nil; lastMapID = nil
        // Never answer against the previous map's localizer while the new one
        // is being chosen; a fix through the wrong map would feed the anchor.
        localizer = nil
        localizerName = ""
        guard let alignment else {
            lastError = "Map not aligned"
            return
        }
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        guard !ImmersalConfig.token.isEmpty, !mapIDs.isEmpty else {
            lastError = ImmersalConfig.token.isEmpty ? "No Immersal token" : "No Immersal map ids"
            return
        }
        camera = GlassesCamera.load()
        running = true
        claim.arm(generation: generation)
        DiagnosticsLog.write("glasses-fix start maps=\(mapIDs)")
        reselectLocalizer()
    }

    func stop() {
        guard running else { return }
        running = false
        claim.disarm()
        DiagnosticsLog.write("glasses-fix stop attempts=\(attempts) fixes=\(fixes)")
    }

    /// On-device or cloud for the running session, as the other localizers
    /// choose it; called at start and again when a map binary lands.
    func reselectLocalizer() {
        guard running, let alignment else { return }
        let generation = self.generation
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        let token = ImmersalConfig.token
        Task { [weak self] in
            let choice = await ImmersalLocalizerFactory.select(mapIDs: mapIDs, token: token, cache: ImmersalMapCache())
            guard let self, self.running, generation == self.generation else { return }
            self.localizer = choice.localizer
            self.localizerName = choice.localizer.name
        }
    }

    /// SDK decode thread. The same shape as `GlassesPositioning.consume`.
    nonisolated func consume(_ frame: AiSeeFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        guard selector.admits(isKeyframe: frame.isKeyframe, now: now),
              let generation = claim.tryClaim(now: now, minimumInterval: GlassesPositioning.minimumInterval) else { return }
        let source = GlassesPositioning.FrameSource(keyframe: frame.isKeyframe, bytes: frame.compressedBytes)
        guard let buffer = frame.pixelBuffer,
              let image = ImmersalFrameEncoder.copyBGRA(from: buffer) else {
            claim.release()
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let gray = ImmersalFrameEncoder.gray(from: image, targetWidth: GlassesPositioning.sentFrameWidth)
            let sharpness = gray.map(FrameSharpness.score) ?? 0
            guard self.selector.admits(sharpness: sharpness, now: now) else {
                self.claim.releaseForRetry(minimumInterval: GlassesPositioning.minimumInterval)
                await self.noteSkipped()
                return
            }
            await self.localize(gray, source: source.with(sharpness: sharpness), arrivedAt: now, generation: generation)
        }
    }

    func setFrameFilter(_ filter: GlassesFrameFilter) {
        selector.set(filter: filter)
    }

    private func noteSkipped() {
        skippedFrames = selector.skippedBlurry + selector.skippedNonKey
    }

    private func localize(_ frame: GrayFrame?, source: GlassesPositioning.FrameSource,
                          arrivedAt: TimeInterval, generation: Int) async {
        defer { claim.release() }
        guard running, generation == self.generation, let alignment, let localizer else { return }
        guard let frame else {
            lastError = "encode"
            return
        }
        let intrinsics = camera.intrinsics(width: frame.width, height: frame.height)
        let result = await localizer.localize(frame, intrinsics: intrinsics)
        guard running, generation == self.generation else { return }
        attempts += 1
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastMapID = result.mapID
        Self.logger.notice("localize \(self.attempts): \(result.success ? "fix" : result.error, privacy: .public) map=\(result.mapID ?? -1) \(self.lastLatencyMS ?? 0) ms")
        DiagnosticsLog.write("glasses-fix localize \(attempts): \(result.success ? "fix" : result.error) map=\(result.mapID ?? -1) \(lastLatencyMS ?? 0) ms \(result.requestBytes) B \(source.logText)")
        guard result.success, let raw = result.pose, let poseInMap = ImmersalPose.cameraPoseInMap(raw) else {
            lastError = result.success ? "malformed pose" : result.error
            if ImmersalConfig.recoverFromRejectedToken(ImmersalConfig.token, error: result.error) {
                lastError = "\(result.error) · typed token dropped, retrying with the built-in one"
            }
            return
        }
        fixes += 1
        lastError = nil
        onFix?(alignment.toGraph(cameraPose: poseInMap, mapID: result.mapID), arrivedAt)
    }
}
