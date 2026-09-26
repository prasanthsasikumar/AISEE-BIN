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

    func start(alignment: ImmersalAlignment?) {
        stop()
        guard let alignment, !alignment.mapIDs.isEmpty else {
            lastError = "map has no Immersal alignment"
            return
        }
        self.alignment = alignment
        anchor.reset()
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
        Self.logger.notice("stopped after \(self.attempts) attempts, \(self.anchor.fixes) fixes")
        DiagnosticsLog.write("phone-immersal stop attempts=\(attempts) fixes=\(anchor.fixes)")
    }

    /// ARKit delegate thread. Copies what the request needs out of the frame
    /// and returns; nothing of `frame` is retained.
    nonisolated func consume(_ frame: ARFrame, trackingNormal: Bool) {
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
        let graphPose = alignment.toGraph(cameraPose: poseInMap)
        if anchor.update(graphPose: graphPose, sessionPose: sessionPose) {
            lastError = nil
            lastFixAt = capturedAt
            let p = NavigationGeometry.planarPosition(of: graphPose)
            Self.logger.notice("fix \(self.anchor.fixes): graph (\(p.x), \(p.y)) jump \(self.anchor.lastJump) m")
            if !wasAnchored { onFirstFix?() }
        } else {
            lastError = String(format: "fix rejected: jumped %.1f m", anchor.lastJump)
            Self.logger.notice("fix rejected: jumped \(self.anchor.lastJump) m")
        }
    }
}
