import CoreMotion
import Foundation
import Observation
import OSLog
import simd

/// Metres walked, from whatever counts steps. Abstracted so the positioning
/// loop can be tested with a scripted distance.
protocol WalkedDistanceSource: AnyObject, Sendable {
    var walkedMetres: Float { get }
    func start()
    func stop()
}

/// `CMPedometer`, which works with the phone in a pocket — the one motion
/// sensor that still does. Distance falls back to steps × 0.7 m on the rare
/// device that reports steps but not distance.
final class PedometerDistance: WalkedDistanceSource, @unchecked Sendable {
    private let pedometer = CMPedometer()
    private let lock = NSLock()
    private var distance: Float = 0
    /// Distance accumulated by previous `start`/`stop` cycles, so restarting
    /// the source never makes the total go backwards.
    private var carried: Float = 0

    var walkedMetres: Float { lock.withLock { carried + distance } }

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            let metres = data.distance.map { Float(truncating: $0) } ?? Float(truncating: data.numberOfSteps) * 0.7
            self.lock.withLock { self.distance = metres }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        lock.withLock {
            carried += distance
            distance = 0
        }
    }
}

/// The glasses' answer to `ARNavigationManager`: a source of `PoseSnapshot`s in
/// the graph frame, built from Immersal fixes on glasses frames and pedometer
/// dead reckoning in between.
///
/// Per decoded frame, at most every `minimumInterval` and never with a request
/// already in flight: copy the pixels, reduce them to gray off-thread, ask
/// the Immersal localizer (the native plugin when the map is cached, else the
/// cloud). A successful fix becomes an ARKit-convention camera pose, is
/// carried into the graph frame by the map's `ImmersalAlignment`, and must
/// pass `FixGate` before it re-anchors the `PoseExtrapolator`. A steady ticker
/// then emits snapshots from the extrapolator so guidance runs at a fixed
/// cadence regardless of how the network behaves.
@MainActor
@Observable
final class GlassesPositioning {

    /// Immersal answers in about a second; sending faster only queues.
    nonisolated static let minimumInterval: TimeInterval = 0.5
    /// Frames are localized at this width. 960 keeps the field of view and halves
    /// the PNG against the native 1280, and the phone probe localized fine at
    /// 960 wide. Intrinsics are derived from the sent size, so this is safe to tune.
    nonisolated static let sentFrameWidth = 960
    /// Cadence of the snapshots between fixes. ARKit gives 60; guidance needs far fewer.
    static let tickInterval: TimeInterval = 0.2

    typealias Localize = @Sendable (_ frame: GrayFrame, _ intrinsics: CameraIntrinsics)
        async -> ImmersalLocalizeResult

    // MARK: Observable state

    private(set) var localizationStatus: LocalizationStatus = .notStarted
    private(set) var cameraTransform = matrix_identity_float4x4
    private(set) var attempts = 0
    private(set) var fixes = 0
    private(set) var rejectedFixes = 0
    private(set) var lastLatencyMS: Int?
    private(set) var lastError: String?
    private(set) var lastMapID: Int?
    private(set) var walkedMetres: Float = 0
    private(set) var secondsSinceFix: TimeInterval?
    private(set) var frameSize: (width: Int, height: Int)?
    /// Where fixes are computed this session: "on device" or "cloud".
    private(set) var localizerName = ""
    /// Frames the selector turned down this session, and the last sent frame's
    /// sharpness (`FrameSharpness.score`).
    private(set) var skippedFrames = 0
    private(set) var lastSharpness: Float?

    var camera = GlassesCamera.load()

    /// Every tick, once there has been a first fix.
    @ObservationIgnored var onPose: ((PoseSnapshot) -> Void)?

    // MARK: Internals

    @ObservationIgnored private var alignment: ImmersalAlignment?
    @ObservationIgnored private var gate = FixGate()
    @ObservationIgnored private var extrapolator = PoseExtrapolator()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let pedometer: WalkedDistanceSource
    @ObservationIgnored private let turnSource: TurnSource
    @ObservationIgnored private var localize: Localize
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0

    /// Touched on the SDK thread: whether a frame may be claimed right now.
    /// Outside the actor so `consume` can run where the decoder calls it.
    @ObservationIgnored private let claim = FrameClaim()
    @ObservationIgnored let selector = GlassesFrameSelector()

    private final class FrameClaim: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        private var lastClaimAt: TimeInterval = -.infinity
        private var generation = 0

        func arm(generation: Int) {
            lock.withLock { self.generation = generation; claimed = false; lastClaimAt = -.infinity }
        }

        func disarm() { lock.withLock { generation = 0; claimed = false } }

        /// Claims this frame for localization, returning the generation it
        /// belongs to, or `nil` when another request is in flight, the last
        /// attempt was too recent, or positioning is not running.
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

    init(pedometer: WalkedDistanceSource = PedometerDistance(),
         turnSource: TurnSource = DeviceMotionTurn(),
         localize: Localize? = nil) {
        self.pedometer = pedometer
        self.turnSource = turnSource
        self.usesDefaultLocalizer = localize == nil
        self.localize = localize ?? { _, _ in
            ImmersalLocalizeResult(success: false, error: "not started", mapID: nil, pose: nil, latency: 0, requestBytes: 0)
        }
        self.localizerName = localize == nil ? "" : "injected"
    }

    /// Chooses the localizer again for the running session, off the main
    /// actor, without touching the extrapolator, the gate or the counters:
    /// called at start, and again when a map binary lands so a cloud session
    /// moves on-device. The ids are the loaded map's own rather than whatever
    /// Settings holds. A localizer injected at init is left alone.
    func reselectLocalizer() {
        guard running, usesDefaultLocalizer else { return }
        let generation = self.generation
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        let token = ImmersalConfig.token
        Task { [weak self] in
            let choice = await ImmersalLocalizerFactory.select(mapIDs: mapIDs, token: token, cache: ImmersalMapCache())
            guard let self, self.running, generation == self.generation else { return }
            let localizer = choice.localizer
            self.localize = { frame, k in await localizer.localize(frame, intrinsics: k) }
            self.localizerName = localizer.name
        }
    }
    @ObservationIgnored private let usesDefaultLocalizer: Bool

    // MARK: - Lifecycle

    /// Begins positioning against `alignment`. Without one there is no way to
    /// place a fix on the graph, and the status says so.
    func start(alignment: ImmersalAlignment?) {
        stop()
        self.alignment = alignment
        generation += 1
        gate.reset()
        extrapolator.reset()
        attempts = 0; fixes = 0; rejectedFixes = 0; skippedFrames = 0; lastSharpness = nil
        selector.reset(filter: GlassesFrameFilter.load(), now: ProcessInfo.processInfo.systemUptime)
        lastError = nil; lastLatencyMS = nil; lastMapID = nil; secondsSinceFix = nil
        guard alignment != nil else {
            localizationStatus = .limited(reason: "Map not aligned")
            return
        }
        let mapIDs = ImmersalConfig.mapIDs(for: alignment)
        guard !ImmersalConfig.token.isEmpty, !mapIDs.isEmpty else {
            localizationStatus = .limited(reason: ImmersalConfig.token.isEmpty ? "No Immersal token" : "No Immersal map ids")
            return
        }
        if usesDefaultLocalizer {
            localizerName = ""
            localize = { _, _ in
                ImmersalLocalizeResult(success: false, error: "choosing localizer", mapID: nil, pose: nil, latency: 0, requestBytes: 0)
            }
        }
        DiagnosticsLog.write("glasses-immersal start maps=\(mapIDs) token=\(ImmersalConfig.token.prefix(6))… frames=\(selector.currentFilter.rawValue)")
        running = true
        claim.arm(generation: generation)
        pedometer.start()
        turnSource.start()
        localizationStatus = .relocalizing
        reselectLocalizer()
        let interval = Self.tickInterval
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        ticker?.cancel()
        ticker = nil
        pedometer.stop()
        turnSource.stop()
        claim.disarm()
        localizationStatus = .notStarted
    }

    var isRunning: Bool { running }

    // MARK: - Frame intake (SDK thread)

    /// Called for every decoded glasses frame. Returns immediately unless this
    /// frame is the one to localize, in which case the pixels are copied here
    /// and everything else happens elsewhere.
    nonisolated func consume(_ frame: AiSeeFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        guard selector.admits(isKeyframe: frame.isKeyframe, now: now),
              let generation = claim.tryClaim(now: now, minimumInterval: Self.minimumInterval) else { return }
        let source = FrameSource(keyframe: frame.isKeyframe, bytes: frame.compressedBytes)
        guard let buffer = frame.pixelBuffer,
              let image = ImmersalFrameEncoder.copyBGRA(from: buffer) else {
            claim.release()
            return
        }
        // The fix describes where the wearer was *now*, not when the answer
        // comes back a second or two later: remember the pedometer reading so
        // the extrapolator can add whatever is walked meanwhile.
        let walkedAtCapture = pedometer.walkedMetres
        let turnAtCapture = turnSource.turn
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let frame = ImmersalFrameEncoder.gray(from: image, targetWidth: Self.sentFrameWidth)
            let sharpness = frame.map(FrameSharpness.score) ?? 0
            guard self.selector.admits(sharpness: sharpness, now: now) else {
                self.claim.releaseForRetry(minimumInterval: Self.minimumInterval)
                await self.noteSkipped()
                return
            }
            await self.localizeCopied(frame, source: source.with(sharpness: sharpness),
                                      capturedAt: now, walkedAtCapture: walkedAtCapture,
                                      turnAtCapture: turnAtCapture, generation: generation)
        }
    }

    /// What the selector knew about a sent frame, for the per-attempt log line.
    struct FrameSource: Sendable {
        var keyframe: Bool
        var bytes: Int
        var sharpness: Float = 0

        func with(sharpness: Float) -> FrameSource {
            var copy = self
            copy.sharpness = sharpness
            return copy
        }

        var logText: String {
            String(format: "sharp=%.0f key=%d kb=%.1f", sharpness, keyframe ? 1 : 0, Double(bytes) / 1000)
        }
    }

    private func noteSkipped() {
        skippedFrames = selector.skippedBlurry + selector.skippedNonKey
    }

    private func localizeCopied(_ frame: GrayFrame?, source: FrameSource,
                                capturedAt: TimeInterval, walkedAtCapture: Float, turnAtCapture: Float,
                                generation: Int) async {
        defer { claim.release() }
        guard running, generation == self.generation else { return }
        guard let frame else {
            lastError = "encode"
            return
        }
        frameSize = (frame.width, frame.height)
        // A sample of what the glasses send, for pulling off a tester's phone.
        if attempts < 3 || attempts % 20 == 0 {
            Task.detached(priority: .utility) {
                guard let png = ImmersalFrameEncoder.png(from: frame) else { return }
                try? png.write(to: DiagnosticsLog.url.deletingLastPathComponent().appendingPathComponent("immersal-glasses-last.png"))
            }
        }
        lastSharpness = source.sharpness
        skippedFrames = selector.skippedBlurry + selector.skippedNonKey
        let intrinsics = camera.intrinsics(width: frame.width, height: frame.height)
        let result = await localize(frame, intrinsics)
        guard running, generation == self.generation else { return }
        apply(result, source: source, capturedAt: capturedAt, walkedAtCapture: walkedAtCapture, turnAtCapture: turnAtCapture)
    }

    /// Localizes one still (the photo-fix test) and, while positioning runs,
    /// applies a fix like any other. Tries the saved focal length first, then
    /// a few others, because the still's field of view is unknown. `other`
    /// stands in when positioning is not running (lanyard or phone mode); its
    /// fixes are only reported.
    func localizeStill(_ frame: GrayFrame, focals: [Float],
                       using other: Localize? = nil) async -> (result: ImmersalLocalizeResult, focalPx: Float) {
        let localize = running ? self.localize : (other ?? self.localize)
        let sharpness = FrameSharpness.score(frame)
        var last = ImmersalLocalizeResult(success: false, error: "no focal", mapID: nil, pose: nil, latency: 0, requestBytes: 0)
        for focal in focals {
            let result = await localize(frame, GlassesCamera(focalPx: focal).intrinsics(width: frame.width, height: frame.height))
            DiagnosticsLog.write(String(format: "glasses-photo %dx%d focal=%.0f sharp=%.0f: %@ map=%d %d ms",
                                        frame.width, frame.height, focal, sharpness,
                                        result.success ? "fix" : result.error, result.mapID ?? -1, Int(result.latency * 1000)))
            last = result
            if result.success {
                if running {
                    apply(result, source: FrameSource(keyframe: true, bytes: frame.pixels.count, sharpness: sharpness),
                          capturedAt: ProcessInfo.processInfo.systemUptime,
                          walkedAtCapture: pedometer.walkedMetres, turnAtCapture: turnSource.turn)
                }
                return (result, focal)
            }
        }
        return (last, focals.last ?? camera.focalPx)
    }

    // MARK: - Applying a fix

    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "positioning")

    private func apply(_ result: ImmersalLocalizeResult, source: FrameSource, capturedAt: TimeInterval,
                       walkedAtCapture walked: Float, turnAtCapture turn: Float) {
        attempts += 1
        Self.logger.notice("localize \(self.attempts): \(result.success ? "fix" : result.error, privacy: .public) map=\(result.mapID ?? -1) \(Int(result.latency * 1000)) ms \(result.requestBytes) B")
        DiagnosticsLog.write("glasses-immersal localize \(attempts): \(result.success ? "fix" : result.error) map=\(result.mapID ?? -1) \(Int(result.latency * 1000)) ms \(result.requestBytes) B walked=\(String(format: "%.1f", walked)) \(source.logText)")
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastMapID = result.mapID
        guard result.success, let raw = result.pose,
              let poseInMap = ImmersalPose.cameraPoseInMap(raw) else {
            lastError = result.success ? "malformed pose" : result.error
            if ImmersalConfig.recoverFromRejectedToken(ImmersalConfig.token, error: result.error) {
                lastError = "\(result.error) · typed token dropped, retrying with the built-in one"
            }
            return
        }
        guard let alignment else { return }
        lastError = nil

        let poseInGraph = alignment.toGraph(cameraPose: poseInMap, mapID: result.mapID)
        let position = NavigationGeometry.planarPosition(of: poseInGraph)
        let heading = NavigationGeometry.heading(of: poseInGraph)

        guard gate.evaluate(position: position, walked: walked) else {
            rejectedFixes += 1
            Self.logger.notice("fix rejected: jumped \(self.gate.lastJump) m after walking \(walked) m")
            DiagnosticsLog.write(String(format: "glasses-immersal fix rejected: jumped %.1f m after walking %.1f m", gate.lastJump, walked))
            lastError = String(format: "fix rejected: jumped %.1f m", gate.lastJump)
            return
        }
        fixes += 1
        Self.logger.notice("fix \(self.fixes): graph (\(position.x), \(position.y)) heading \(heading * 180 / .pi) deg, walked \(walked) m")
        DiagnosticsLog.write(String(format: "glasses-immersal fix %d: graph (%.2f, %.2f) heading %.0f deg walked %.1f m gyro %.0f deg", fixes, position.x, position.y, heading * 180 / .pi, walked, turn * 180 / .pi))
        extrapolator.anchor(position: position, heading: heading, walked: walked, turn: turn, time: capturedAt)
        tick()
    }

    // MARK: - Ticking

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let walked = pedometer.walkedMetres
        walkedMetres = walked
        guard let transform = extrapolator.cameraTransform(walked: walked, turn: turnSource.turn), let fix = extrapolator.fix else {
            localizationStatus = .relocalizing
            return
        }
        secondsSinceFix = now - fix.time
        let stale = extrapolator.isStale(at: now)
        cameraTransform = transform
        localizationStatus = stale ? .limited(reason: "No fix") : .trackingReady
        onPose?(PoseSnapshot(cameraTransform: transform, timestamp: now,
                             trackingReliable: !stale, featurePointCount: 0))
    }
}
