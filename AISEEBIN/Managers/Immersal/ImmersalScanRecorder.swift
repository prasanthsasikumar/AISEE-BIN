import ARKit
import Foundation
import os
import simd

/// Turns an Author walk into an Immersal map. Picks sharp, well-spaced ARKit
/// frames (`ScanFramePolicy`), encodes each as a full-size grayscale PNG with
/// ARKit's pose and intrinsics, and uploads them in order in the background.
/// When the walk is published, `construct` asks Immersal to build the map on
/// those poses, so its frame is ARKit's session frame and the places marked on
/// the walk need no alignment.
@MainActor
@Observable
final class ImmersalScanRecorder {
    private static let logger = Logger(subsystem: "org.ahlab.aisee-bin", category: "immersal-scan")

    private(set) var running = false
    private(set) var captured = 0
    private(set) var uploaded = 0
    private(set) var failed = 0
    private(set) var tooFast = false
    private(set) var lastError: String?
    var queued: Int { captured - uploaded - failed }

    @ObservationIgnored private var generation = 0
    /// Three uploads in flight at once; each lane keeps its own order, and the
    /// explicit image index keeps the server's order across lanes.
    @ObservationIgnored private var lanes: [Task<Void, Never>?] = [nil, nil, nil]
    @ObservationIgnored private let gate = Gate()

    /// The part ARKit's thread touches: the frame policy behind a lock, so no
    /// hop to the main actor is needed to drop the frames that are not wanted.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false
        private var policy = ScanFramePolicy()
        private var nextIndex = 0

        func arm() { lock.withLock { armed = true; policy.reset(); nextIndex = 0 } }
        func rearm() { lock.withLock { armed = true } }
        func disarm() { lock.withLock { armed = false } }
        /// nil when not armed; otherwise whether to capture, whether the phone is
        /// moving too fast, and the index this capture takes.
        func decide(transform: simd_float4x4, timestamp: TimeInterval, trackingNormal: Bool) -> (capture: Bool, tooFast: Bool, index: Int)? {
            lock.withLock {
                guard armed else { return nil }
                let take = policy.shouldCapture(transform: transform, timestamp: timestamp, trackingNormal: trackingNormal)
                let index = nextIndex
                if take { nextIndex += 1 }
                return (take, policy.tooFast, index)
            }
        }
    }

    private struct Shot: Sendable {
        var plane: ImmersalFrameEncoder.LumaPlane
        var intrinsics: (fx: Float, fy: Float, ox: Float, oy: Float)
        var pose: ImmersalCapturePose.Encoded
        var index: Int
        var anchor: Bool
    }

    /// Starts a scan; `clearing` empties the account's workspace first.
    func start(clearing: Bool) async {
        stop()
        generation += 1
        let gen = generation
        captured = 0; uploaded = 0; failed = 0; lastError = nil; tooFast = false
        if clearing {
            do { try await ImmersalMappingClient(token: ImmersalConfig.token).clearWorkspace() }
            catch { lastError = error.localizedDescription; Self.logger.notice("clear failed: \(error.localizedDescription, privacy: .public)") }
        }
        guard gen == generation else { return }
        gate.arm()
        running = true
        DiagnosticsLog.write("immersal-scan start (cleared=\(clearing))")
    }

    func stop() {
        guard running else { return }
        gate.disarm()
        running = false
        DiagnosticsLog.write("immersal-scan stop captured=\(captured) uploaded=\(uploaded) failed=\(failed)")
    }

    /// Carries on after a `stop`, keeping counts and image indices.
    func resume() {
        guard !running, generation > 0 else { return }
        gate.rearm()
        running = true
        DiagnosticsLog.write("immersal-scan resume at \(captured) photos")
    }

    /// ARKit's delegate thread. Cheap decision, then the copy and the hop.
    nonisolated func consume(_ frame: ARFrame, trackingNormal: Bool) {
        let transform = frame.camera.transform
        guard let decision = gate.decide(transform: transform, timestamp: frame.timestamp, trackingNormal: trackingNormal) else { return }
        let fast = decision.tooFast
        Task { @MainActor in if self.tooFast != fast { self.tooFast = fast } }
        guard decision.capture, let plane = ImmersalFrameEncoder.copyLuma(from: frame.capturedImage) else { return }
        let shot = Shot(plane: plane,
                        intrinsics: ImmersalFrameEncoder.scaledIntrinsics(frame.camera.intrinsics, factor: 1),
                        pose: ImmersalCapturePose.encode(cameraTransform: transform),
                        index: decision.index, anchor: decision.index == 0)
        Task { @MainActor in self.enqueue(shot) }
    }

    private func enqueue(_ shot: Shot) {
        captured += 1
        let gen = generation
        let lane = shot.index % lanes.count
        let previous = lanes[lane]
        let task = Task { [weak self] in
            _ = await previous?.value          // keep server-side order
            let png = await Task.detached(priority: .utility) {
                ImmersalFrameEncoder.grayscalePNG(from: shot.plane, factor: 1)
            }.value
            guard let self, await self.generation == gen else { return }
            guard let png else { await self.noteFailure("encode", index: shot.index); return }
            let client = ImmersalMappingClient(token: ImmersalConfig.token)
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    try await client.capture(png: png, pose: shot.pose,
                                             fx: shot.intrinsics.fx, fy: shot.intrinsics.fy,
                                             ox: shot.intrinsics.ox, oy: shot.intrinsics.oy,
                                             run: 0, index: shot.index, anchor: shot.anchor)
                    await self.noteUploaded(index: shot.index, bytes: png.count)
                    return
                } catch {
                    lastError = error
                    if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
                }
            }
            await self.noteFailure(lastError?.localizedDescription ?? "upload failed", index: shot.index)
        }
        lanes[lane] = task
    }

    private func noteUploaded(index: Int, bytes: Int) {
        uploaded += 1
        DiagnosticsLog.write("immersal-scan uploaded #\(index) \(bytes) B (\(uploaded)/\(captured))")
    }

    private func noteFailure(_ text: String, index: Int) {
        failed += 1
        lastError = text
        Self.logger.notice("upload #\(index) failed: \(text, privacy: .public)")
        DiagnosticsLog.write("immersal-scan upload #\(index) FAILED: \(text)")
    }

    /// Waits for every queued upload to finish.
    func drain() async {
        for task in lanes { _ = await task?.value }
        lanes = [nil, nil, nil]
    }

    /// Builds the map from what was uploaded. Returns Immersal's map id.
    func construct(name: String) async throws -> Int {
        await drain()
        guard uploaded > 0 else { throw ImmersalMappingClient.Failure(message: "no photos were uploaded") }
        let id = try await ImmersalMappingClient(token: ImmersalConfig.token).construct(name: name, preservePoses: true)
        DiagnosticsLog.write("immersal-scan construct \"\(name)\" from \(uploaded) photos → map \(id)")
        return id
    }

    /// Polls until the map is done or failed; reports the status text.
    func waitForConstruction(of mapID: Int, every seconds: TimeInterval = 15,
                             progress: @MainActor (String) -> Void) async -> Bool {
        let client = ImmersalMappingClient(token: ImmersalConfig.token)
        for _ in 0..<80 {          // twenty minutes at most
            if let status = try? await client.status(of: mapID) {
                progress(status.status)
                if status.status == "done" { return true }
                if status.status == "failed" { return false }
            }
            try? await Task.sleep(for: .seconds(seconds))
        }
        return false
    }
}
