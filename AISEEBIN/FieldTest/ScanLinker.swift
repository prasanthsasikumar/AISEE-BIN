import ARKit
import Foundation
import os
import simd

/// The "link scans" walk: while the phone walks the route with ARKit
/// tracking, frames go to Immersal against one scan at a time, in turn, and
/// every fix is kept with ARKit's pose for that frame. `ScanLinkSolver` then
/// joins the scans through the session, which places each scan in the map to
/// centimetres wherever two scans were seen within a few seconds of each other.
///
/// Cloud only (one scan per `/localizeb64` request), so it needs internet.
@MainActor
@Observable
final class ScanLinker {
    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "scan-link")

    struct MapStat: Identifiable, Equatable {
        let id: Int
        var name: String
        var tries = 0
        var fixes = 0
    }

    private(set) var running = false
    private(set) var stats: [MapStat] = []
    private(set) var samples: [ScanLinkSolver.Sample] = []
    private(set) var lastError: String?

    /// Frames go out at most this often, two requests at a time.
    static let interval: TimeInterval = 0.5
    static let maxInFlight = 2

    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private let gate = Gate()
    @ObservationIgnored private var token = ""

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false, inFlight = 0, last: TimeInterval = -.infinity
        func arm() { lock.withLock { armed = true; inFlight = 0; last = -.infinity } }
        func disarm() { lock.withLock { armed = false } }
        func claim(now: TimeInterval) -> Bool {
            lock.withLock {
                guard armed, inFlight < ScanLinker.maxInFlight, now - last >= ScanLinker.interval else { return false }
                inFlight += 1; last = now; return true
            }
        }
        func release() { lock.withLock { inFlight = max(0, inFlight - 1) } }
    }

    func start(maps: [(id: Int, name: String)], token: String) {
        stats = maps.map { MapStat(id: $0.id, name: $0.name) }
        samples = []
        lastError = maps.count < 2 ? "This map has only one scan; nothing to link." : nil
        self.token = token
        nextIndex = 0
        running = true
        gate.arm()
        DiagnosticsLog.write("scan-link start maps=\(maps.map(\.id))")
    }

    func stop() {
        guard running else { return }
        running = false
        gate.disarm()
        DiagnosticsLog.write("scan-link stop samples=\(samples.count) " + stats.map { "\($0.id):\($0.fixes)/\($0.tries)" }.joined(separator: " "))
    }

    /// ARKit delegate thread, like `PhoneImmersalLocalizer.consume`.
    nonisolated func consume(_ frame: ARFrame, trackingNormal: Bool) {
        guard trackingNormal, gate.claim(now: frame.timestamp) else { return }
        guard let plane = ImmersalFrameEncoder.copyLuma(from: frame.capturedImage) else { gate.release(); return }
        let intrinsics = ImmersalFrameEncoder.scaledIntrinsics(frame.camera.intrinsics)
        let sessionPose = frame.camera.transform
        let time = frame.timestamp
        Task { [weak self] in
            let gray = await Task.detached(priority: .userInitiated) { ImmersalFrameEncoder.packedLuma(from: plane) }.value
            guard let self else { return }
            await self.localize(gray, intrinsics: intrinsics, sessionPose: sessionPose, time: time)
        }
    }

    private func localize(_ frame: GrayFrame?, intrinsics: CameraIntrinsics, sessionPose: simd_float4x4, time: TimeInterval) async {
        defer { gate.release() }
        guard running, let frame, !stats.isEmpty else { return }
        let index = nextIndex % stats.count
        nextIndex += 1
        let mapID = stats[index].id
        let result = await CloudImmersalLocalizer(token: token, mapIDs: [mapID]).localize(frame, intrinsics: intrinsics)
        guard running, let i = stats.firstIndex(where: { $0.id == mapID }) else { return }
        stats[i].tries += 1
        guard result.success, let raw = result.pose, let poseInScan = ImmersalPose.cameraPoseInMap(raw) else {
            if !result.success, result.error != "none" { lastError = result.error }
            return
        }
        stats[i].fixes += 1
        lastError = nil
        let fromSession = Placement4.between(poseInA: poseInScan, poseInB: sessionPose)
        samples.append(.init(mapID: mapID, time: time, fromSession: fromSession))
        DiagnosticsLog.write(String(format: "scan-link fix map=%d t=%.1f yaw=%.3f t=(%.2f, %.2f, %.2f) %d ms",
                                    mapID, time, fromSession.yaw, fromSession.tx, fromSession.ty, fromSession.tz,
                                    Int(result.latency * 1000)))
    }

    /// Where every linked scan sits, keeping `reference` where it is now.
    func solve(reference: Int, referencePlacement: Placement4) -> [Int: ScanLinkSolver.Link] {
        ScanLinkSolver().solve(samples: samples, reference: reference, referencePlacement: referencePlacement)
    }
}
