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
/// already in flight: copy the pixels, encode a grayscale PNG off-thread, ask
/// Immersal. A successful fix becomes an ARKit-convention camera pose, is
/// carried into the graph frame by the map's `ImmersalAlignment`, and must
/// pass `FixGate` before it re-anchors the `PoseExtrapolator`. A steady ticker
/// then emits snapshots from the extrapolator so guidance runs at a fixed
/// cadence regardless of how the network behaves.
@MainActor
@Observable
final class GlassesPositioning {

    /// Immersal answers in about a second; sending faster only queues.
    nonisolated static let minimumInterval: TimeInterval = 0.5
    /// Frames are sent at this width. 960 keeps the field of view and halves
    /// the PNG against the native 1280, and the phone probe localized fine at
    /// 960 wide. Intrinsics are derived from the sent size, so this is safe to tune.
    nonisolated static let sentFrameWidth = 960
    /// Cadence of the snapshots between fixes. ARKit gives 60; guidance needs far fewer.
    static let tickInterval: TimeInterval = 0.2

    typealias Localize = @Sendable (_ png: Data, _ intrinsics: (fx: Float, fy: Float, ox: Float, oy: Float))
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

    var camera = GlassesCamera.load()

    /// Every tick, once there has been a first fix.
    @ObservationIgnored var onPose: ((PoseSnapshot) -> Void)?

    // MARK: Internals

    @ObservationIgnored private var alignment: ImmersalAlignment?
    @ObservationIgnored private var gate = FixGate()
    @ObservationIgnored private var extrapolator = PoseExtrapolator()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let pedometer: WalkedDistanceSource
    @ObservationIgnored private let localize: Localize
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0

    /// Touched on the SDK thread: whether a frame may be claimed right now.
    /// Outside the actor so `consume` can run where the decoder calls it.
    @ObservationIgnored private let claim = FrameClaim()

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
    }

    init(pedometer: WalkedDistanceSource = PedometerDistance(), localize: Localize? = nil) {
        self.pedometer = pedometer
        self.localize = localize ?? { png, k in
            await ImmersalClient(token: ImmersalConfig.token, mapIDs: ImmersalConfig.mapIDs)
                .localize(pngData: png, fx: k.fx, fy: k.fy, ox: k.ox, oy: k.oy)
        }
    }

    // MARK: - Lifecycle

    /// Begins positioning against `alignment`. Without one there is no way to
    /// place a fix on the graph, and the status says so.
    func start(alignment: ImmersalAlignment?) {
        stop()
        self.alignment = alignment
        generation += 1
        gate.reset()
        extrapolator.reset()
        attempts = 0; fixes = 0; rejectedFixes = 0
        lastError = nil; lastLatencyMS = nil; lastMapID = nil; secondsSinceFix = nil
        guard alignment != nil else {
            localizationStatus = .limited(reason: "Map not aligned")
            return
        }
        guard ImmersalConfig.isConfigured else {
            localizationStatus = .limited(reason: "No Immersal token")
            return
        }
        running = true
        claim.arm(generation: generation)
        pedometer.start()
        localizationStatus = .relocalizing
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
        guard let generation = claim.tryClaim(now: now, minimumInterval: Self.minimumInterval) else { return }
        guard let buffer = frame.pixelBuffer,
              let image = ImmersalFrameEncoder.copyBGRA(from: buffer) else {
            claim.release()
            return
        }
        // The fix describes where the wearer was *now*, not when the answer
        // comes back a second or two later: remember the pedometer reading so
        // the extrapolator can add whatever is walked meanwhile.
        let walkedAtCapture = pedometer.walkedMetres
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let encoded = ImmersalFrameEncoder.grayscalePNG(from: image, targetWidth: Self.sentFrameWidth)
            await self.localizeCopied(encoded, capturedAt: now, walkedAtCapture: walkedAtCapture,
                                      generation: generation)
        }
    }

    private func localizeCopied(_ encoded: (png: Data, width: Int, height: Int)?,
                                capturedAt: TimeInterval, walkedAtCapture: Float, generation: Int) async {
        defer { claim.release() }
        guard running, generation == self.generation else { return }
        guard let encoded else {
            lastError = "encode"
            return
        }
        frameSize = (encoded.width, encoded.height)
        let intrinsics = camera.intrinsics(width: encoded.width, height: encoded.height)
        let result = await localize(encoded.png, intrinsics)
        guard running, generation == self.generation else { return }
        apply(result, capturedAt: capturedAt, walkedAtCapture: walkedAtCapture)
    }

    // MARK: - Applying a fix

    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "positioning")

    private func apply(_ result: ImmersalLocalizeResult, capturedAt: TimeInterval, walkedAtCapture walked: Float) {
        attempts += 1
        Self.logger.notice("localize \(self.attempts): \(result.success ? "fix" : result.error, privacy: .public) map=\(result.mapID ?? -1) \(Int(result.latency * 1000)) ms \(result.requestBytes) B")
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastMapID = result.mapID
        guard result.success, let raw = result.pose,
              let poseInMap = ImmersalPose.cameraPoseInMap(raw) else {
            lastError = result.success ? "malformed pose" : result.error
            return
        }
        guard let alignment else { return }
        lastError = nil

        let poseInGraph = alignment.toGraph(cameraPose: poseInMap)
        let position = NavigationGeometry.planarPosition(of: poseInGraph)
        let heading = NavigationGeometry.heading(of: poseInGraph)

        guard gate.evaluate(position: position, walked: walked) else {
            rejectedFixes += 1
            Self.logger.notice("fix rejected: jumped \(self.gate.lastJump) m after walking \(walked) m")
            lastError = String(format: "fix rejected: jumped %.1f m", gate.lastJump)
            return
        }
        fixes += 1
        Self.logger.notice("fix \(self.fixes): graph (\(position.x), \(position.y)) heading \(heading * 180 / .pi) deg, walked \(walked) m")
        extrapolator.anchor(position: position, heading: heading, walked: walked, time: capturedAt)
        tick()
    }

    // MARK: - Ticking

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let walked = pedometer.walkedMetres
        walkedMetres = walked
        guard let transform = extrapolator.cameraTransform(walked: walked), let fix = extrapolator.fix else {
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
