import ARKit
import Foundation
import os
import simd

/// Positions the phone in a map that has an Immersal alignment but no ARKit
/// world map: an imported map, drawn in the web editor on Immersal's cloud.
///
/// Consumes ARKit frames. Roughly once a second, while ARKit tracking is
/// normal, one frame goes to the Immersal localizer (the native plugin when
/// the map is cached, else `/localizeb64`) with ARKit's own intrinsics; the
/// answer, carried into the graph frame by the map's alignment, is paired with
/// ARKit's pose for that frame and handed to `ImmersalAnchor`. Between fixes
/// every ARKit frame is mapped through the anchor, so guidance runs on smooth
/// motion. Mirrors `GlassesPositioning`, minus the pedometer: ARKit is the
/// odometry here.
@MainActor
@Observable
final class PhoneImmersalLocalizer {
    private static let logger = Logger(subsystem: "org.ahlab.aisee-bin", category: "phone-immersal")

    static let localizeInterval: TimeInterval = 1.2

    private(set) var anchor = ImmersalAnchor()
    private(set) var attempts = 0
    private(set) var lastError: String?
    private(set) var lastLatencyMS = 0
    private(set) var lastMapID: Int?
    private(set) var lastFixAt: TimeInterval?
    private(set) var running = false
    /// Where fixes are computed this session: "on device" or "cloud".
    private(set) var localizerName = ""

    /// Fired once per `start`, on the first accepted fix.
    @ObservationIgnored var onFirstFix: (() -> Void)?

    @ObservationIgnored private var alignment: ImmersalAlignment?
    @ObservationIgnored private var localizer: (any ImmersalLocalizer)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let claim = Claim()

    /// Fixes offered by the glasses camera in lanyard mode (position only).
    private(set) var glassesFixes = 0
    /// Glasses frame → phone latency: how far back in the ARKit history a
    /// glasses fix is paired. Persisted; tuned on the Glasses screen.
    var streamLatency: TimeInterval = UserDefaults.standard.object(forKey: "glasses.streamLatency") as? Double ?? 0.2 {
        didSet { UserDefaults.standard.set(streamLatency, forKey: "glasses.streamLatency") }
    }
    @ObservationIgnored private var bootstrap = PositionPairBootstrap()
    @ObservationIgnored private let history = HistoryBox()

    /// ARKit poses, written on ARKit's thread and read on the main actor.
    /// Recording is opt-in (lanyard mode) so phone mode pays nothing.
    private final class HistoryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var history = PoseHistory()
        private var enabled = false
        func set(enabled: Bool) {
            lock.withLock {
                self.enabled = enabled
                if !enabled { history.reset() }
            }
        }
        func record(_ t: simd_float4x4, at time: TimeInterval) {
            lock.withLock { if enabled { history.record(t, at: time) } }
        }
        func pose(at time: TimeInterval) -> simd_float4x4? { lock.withLock { history.pose(at: time) } }
    }

    /// Frames arrive on ARKit's queue; the claim decides, without hopping to
    /// the main actor, whether this one starts a request.
    private final class Claim: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 0
        private var inFlight = false
        private var lastAttempt: TimeInterval = -.infinity

        func arm(generation: Int) { lock.withLock { self.generation = generation; inFlight = false; lastAttempt = -.infinity } }
        func disarm() { lock.withLock { generation = 0; inFlight = false } }
        func tryClaim(now: TimeInterval, minimumInterval: TimeInterval) -> Int? {
            lock.withLock {
                guard generation > 0, !inFlight, now - lastAttempt >= minimumInterval else { return nil }
                inFlight = true; lastAttempt = now
                return generation
            }
        }
        func release() { lock.withLock { inFlight = false } }
    }

    var isAnchored: Bool { anchor.isAnchored }
    var fixes: Int { anchor.fixes }

    func toGraph(_ sessionPose: simd_float4x4) -> simd_float4x4? { anchor.toGraph(sessionPose) }

    func start(alignment: ImmersalAlignment?, recordHistory: Bool = false) {
        stop()
        guard let alignment, !alignment.mapIDs.isEmpty else {
            lastError = "map has no Immersal alignment"
            return
        }
        self.alignment = alignment
        anchor.reset()
        bootstrap.reset()
        glassesFixes = 0
        history.set(enabled: recordHistory)
        attempts = 0
        lastError = nil
        lastFixAt = nil
        generation += 1
        claim.arm(generation: generation)
        running = true
        Self.logger.notice("started against maps \(alignment.mapIDs, privacy: .public)")
        let token = ImmersalConfig.token
        DiagnosticsLog.write("phone-immersal start maps=\(alignment.mapIDs) token=\(token.prefix(6))… \(ImmersalConfig.storedToken.isEmpty ? "built-in" : "typed") bundled=\(ImmersalConfig.hasBundledToken)")
        localizer = nil
        localizerName = ""
        reselectLocalizer()
    }

    /// Chooses the localizer again for the running session, off the main
    /// actor, without touching the anchor or the counters: called at start,
    /// and again when a map binary lands so a cloud session moves on-device.
    func reselectLocalizer() {
        guard running, let alignment else { return }
        let generation = self.generation
        let mapIDs = alignment.mapIDs
        let token = ImmersalConfig.token
        Task { [weak self] in
            let choice = await ImmersalLocalizerFactory.select(mapIDs: mapIDs, token: token, cache: ImmersalMapCache())
            guard let self, self.running, generation == self.generation else { return }
            self.localizer = choice.localizer
            self.localizerName = choice.localizer.name
        }
    }

    func stop() {
        guard running else { return }
        running = false
        claim.disarm()
        history.set(enabled: false)
        Self.logger.notice("stopped after \(self.attempts) attempts, \(self.anchor.fixes) fixes")
        DiagnosticsLog.write("phone-immersal stop attempts=\(attempts) fixes=\(anchor.fixes)")
    }

    /// ARKit delegate thread. Copies what the request needs out of the frame
    /// and returns; nothing of `frame` is retained.
    nonisolated func consume(_ frame: ARFrame, trackingNormal: Bool) {
        if trackingNormal { history.record(frame.camera.transform, at: frame.timestamp) }
        guard trackingNormal,
              let generation = claim.tryClaim(now: frame.timestamp, minimumInterval: Self.localizeInterval)
        else { return }
        guard let plane = ImmersalFrameEncoder.copyLuma(from: frame.capturedImage) else {
            claim.release()
            DiagnosticsLog.write("phone-immersal frame: could not copy luma")
            return
        }
        let intrinsics = ImmersalFrameEncoder.scaledIntrinsics(frame.camera.intrinsics)
        let sessionPose = frame.camera.transform
        let capturedAt = frame.timestamp
        let token = ImmersalConfig.token
        Task { [weak self] in
            let frame = await Task.detached(priority: .userInitiated) {
                ImmersalFrameEncoder.packedLuma(from: plane)
            }.value
            guard let self else { return }
            await self.localize(frame, intrinsics: intrinsics, sessionPose: sessionPose,
                                capturedAt: capturedAt, token: token, generation: generation)
        }
    }

    private func localize(_ frame: GrayFrame?,
                          intrinsics: CameraIntrinsics,
                          sessionPose: simd_float4x4,
                          capturedAt: TimeInterval,
                          token: String,
                          generation: Int) async {
        defer { claim.release() }
        guard generation == self.generation, running, let alignment, let localizer else { return }
        guard let frame else { lastError = "encode"; DiagnosticsLog.write("phone-immersal encode failed"); return }
        // Keep a recent frame as sent, so it can be pulled off a tester's phone
        // and run against Immersal by hand when nothing matches. The first few
        // after a start and then one in twenty: enough to see, cheap on disk.
        if attempts < 3 || attempts % 20 == 0 {
            DiagnosticsLog.write(String(format: "phone-immersal frame %dx%d fx=%.0f fy=%.0f ox=%.0f oy=%.0f via %@", frame.width, frame.height, intrinsics.fx, intrinsics.fy, intrinsics.ox, intrinsics.oy, localizer.name))
            Task.detached(priority: .utility) {
                guard let png = ImmersalFrameEncoder.png(from: frame) else { return }
                try? png.write(to: DiagnosticsLog.url.deletingLastPathComponent().appendingPathComponent("immersal-last.png"))
            }
        }
        let result = await localizer.localize(frame, intrinsics: intrinsics)
        guard generation == self.generation, running else { return }
        apply(result, sessionPose: sessionPose, capturedAt: capturedAt, alignment: alignment, token: token)
    }

    private func apply(_ result: ImmersalLocalizeResult,
                       sessionPose: simd_float4x4,
                       capturedAt: TimeInterval,
                       alignment: ImmersalAlignment,
                       token: String) {
        attempts += 1
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastMapID = result.mapID
        Self.logger.notice("localize \(self.attempts): \(result.success ? "fix" : result.error, privacy: .public) map=\(result.mapID ?? -1) \(self.lastLatencyMS) ms")
        DiagnosticsLog.write("phone-immersal localize \(attempts): \(result.success ? "fix" : result.error) map=\(result.mapID ?? -1) \(lastLatencyMS) ms \(result.requestBytes) B")
        guard result.success, let raw = result.pose, let poseInMap = ImmersalPose.cameraPoseInMap(raw) else {
            lastError = result.success ? "malformed pose" : result.error
            if ImmersalConfig.recoverFromRejectedToken(token, error: result.error) {
                lastError = "\(result.error) · typed token dropped, retrying with the built-in one"
                Self.logger.notice("token rejected (\(result.error, privacy: .public)); reverted to the built-in token")
            }
            return
        }
        let wasAnchored = anchor.isAnchored
        let graphPose = alignment.toGraph(cameraPose: poseInMap, mapID: result.mapID)
        if anchor.update(graphPose: graphPose, sessionPose: sessionPose) {
            lastError = nil
            bootstrap.reset()
            lastFixAt = capturedAt
            let p = NavigationGeometry.planarPosition(of: graphPose)
            Self.logger.notice("fix \(self.anchor.fixes): graph (\(p.x), \(p.y)) jump \(self.anchor.lastJump) m")
            if !wasAnchored { onFirstFix?() }
        } else {
            lastError = String(format: "fix rejected: jumped %.1f m", anchor.lastJump)
            Self.logger.notice("fix rejected: jumped \(self.anchor.lastJump) m")
        }
    }

    /// A glasses fix in lanyard mode: position only, paired with the session
    /// pose from when the frame was shot (arrival minus the stream latency).
    /// With an anchor it nudges the translation; without one it feeds the
    /// bootstrap until that solves.
    func offer(glassesFix graphPose: simd_float4x4, arrivedAt: TimeInterval) {
        guard running else { return }
        guard let sessionPose = history.pose(at: arrivedAt - streamLatency) else {
            lastError = "glasses fix: no ARKit pose for that moment"
            DiagnosticsLog.write("glasses-fix dropped: no session pose within 0.5 s")
            return
        }
        glassesFixes += 1
        let graphPosition = NavigationGeometry.planarPosition(of: graphPose)
        if anchor.isAnchored {
            if anchor.updatePosition(graphPosition: graphPosition, sessionPose: sessionPose) {
                lastError = nil
                lastFixAt = arrivedAt
                DiagnosticsLog.write(String(format: "glasses-fix %d: graph (%.2f, %.2f) jump %.1f m", glassesFixes, graphPosition.x, graphPosition.y, anchor.lastJump))
            } else {
                lastError = String(format: "glasses fix rejected: jumped %.1f m", anchor.lastJump)
                DiagnosticsLog.write(String(format: "glasses-fix rejected: jumped %.1f m", anchor.lastJump))
            }
            return
        }
        let s = sessionPose.columns.3, g = graphPose.columns.3
        bootstrap.add(session: SIMD3(s.x, s.y, s.z), graph: SIMD3(g.x, g.y, g.z))
        DiagnosticsLog.write("glasses-fix bootstrap pair \(bootstrap.pairs.count)")
        guard let fit = bootstrap.solve() else { return }
        anchor.install(fit: fit)
        bootstrap.reset()
        lastError = nil
        lastFixAt = arrivedAt
        DiagnosticsLog.write(String(format: "glasses-fix anchored by bootstrap: yaw %.0f deg t (%.1f, %.1f)", fit.yaw * 180 / .pi, fit.tx, fit.tz))
        onFirstFix?()
    }
}
