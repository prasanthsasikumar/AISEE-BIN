import ARKit
import Foundation
import Observation
import simd

// THROWAWAY — see ImmersalPose.swift.

/// Runs one measured walk: samples ARKit, localizes against Immersal on a timer,
/// records ground-truth stamps, and writes it all to one CSV.
///
/// Both systems are observed on the *same* frames of the *same* ARKit session,
/// so nothing about the comparison depends on walking the route twice.
@MainActor
@Observable
final class ProbeSession {

    enum State: Equatable {
        case idle
        case running
        case finished(URL)
    }

    /// Every 2 s. Fast enough to see a fix arrive and to bound drift between
    /// fixes; slow enough that a 20-minute walk is ~600 requests rather than
    /// tens of thousands, and that weak Wi-Fi has a chance of keeping up.
    static let localizeInterval: TimeInterval = 2.0
    /// 10 Hz of ARKit pose is plenty to reconstruct a walking trajectory.
    static let arSampleInterval: TimeInterval = 0.1
    /// Beyond this, stop hoarding images — the walk matters more than the queue.
    static let pendingLimit = 400

    /// The Immersal maps this walk localizes against: the loaded map's own,
    /// when it has an alignment, else what Settings holds. Set before `start`.
    var mapIDs: [Int] = ImmersalConfig.mapIDs

    private(set) var state: State = .idle
    private(set) var attempts = 0
    private(set) var successes = 0
    private(set) var rowCount = 0
    private(set) var lastError: String?
    private(set) var lastLatencyMS: Int?
    private(set) var lastMapID: Int?
    private(set) var lastDisagreement: Float?
    private(set) var lastStampLabel: String?
    /// The protocol marker most recently tapped, with the walk time it was
    /// tapped at, so the button shows that it took.
    private(set) var lastMarker: (label: String, elapsed: TimeInterval)?
    private(set) var pendingCount = 0
    private(set) var isReplaying = false
    /// Provisional map-space position of the latest fix, for the live readout
    /// only. Never a reported number — see `ImmersalPoseConvention`.
    private(set) var lastFixPosition: SIMD3<Float>?
    /// Fixes that arrived while ARKit was tracking normally and agreed with its
    /// odometry: the raw material for an `ImmersalAlignment`.
    private(set) var alignmentPairs: [ImmersalAlignment.Pair] = []

    private var log: ProbeLog?
    private var startedAt: Date?
    private var lastLocalizeAt: TimeInterval = -.infinity
    private var lastARSampleAt: TimeInterval = -.infinity
    private var requestInFlight = false

    /// Previous successful fix and the ARKit pose at that same instant, for the
    /// convention-free odometry cross-check.
    private var previousFix: ImmersalRawPose?
    private var previousFixAR: simd_float4x4?

    private var pending: [PendingFrame] = []
    private let pendingDirectory: URL

    private struct PendingFrame {
        let sequence: Int
        let elapsed: TimeInterval
        let arTransform: simd_float4x4
        let fx, fy, ox, oy: Float
        let url: URL
    }
    private var pendingSequence = 0

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        pendingDirectory = directory.appendingPathComponent("probe-pending", isDirectory: true)
    }

    // MARK: - Lifecycle

    func start() {
        guard state != .running else { return }
        do {
            let now = Date()
            log = try ProbeLog(startedAt: now)
            startedAt = now
            try? FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            attempts = 0; successes = 0; rowCount = 0
            lastError = nil; lastLatencyMS = nil; lastMapID = nil
            lastDisagreement = nil; lastFixPosition = nil; lastStampLabel = nil; lastMarker = nil
            alignmentPairs = []
            previousFix = nil; previousFixAR = nil
            lastLocalizeAt = -.infinity; lastARSampleAt = -.infinity
            state = .running
            marker("probe started · maps \(mapIDs.map(String.init).joined(separator: "+")) · downscale \(ImmersalFrameEncoder.downscale)")
        } catch {
            lastError = "could not open log: \(error.localizedDescription)"
        }
    }

    func finish() {
        guard state == .running, let log else { return }
        marker("probe finished · \(successes)/\(attempts) fixes · \(pending.count) queued")
        log.close()
        state = .finished(log.url)
        self.log = nil
    }

    // MARK: - Frame intake

    /// Called for every ARKit frame while the probe is running.
    ///
    /// Does the minimum on the main actor: a `memcpy` of the luma plane, then
    /// hands off. The `ARFrame` is never retained.
    func consume(frame: ARFrame, trackingState: ARCamera.TrackingState) {
        guard state == .running, let log, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let transform = frame.camera.transform
        var trackingNormal = false
        if case .normal = trackingState { trackingNormal = true }

        if elapsed - lastARSampleAt >= Self.arSampleInterval {
            lastARSampleAt = elapsed
            append(ProbeLogRow(event: .frame,
                               elapsed: elapsed,
                               arPosition: position(of: transform),
                               arOrientation: simd_quatf(rotation(of: transform)),
                               arTrackingState: trackingState.probeLabel,
                               arMappingStatus: frame.worldMappingStatus.probeLabel,
                               arFeaturePoints: frame.rawFeaturePoints?.points.count ?? 0),
                   to: log)
        }

        guard elapsed - lastLocalizeAt >= Self.localizeInterval,
              !requestInFlight,
              !ImmersalConfig.token.isEmpty, !mapIDs.isEmpty,
              let plane = ImmersalFrameEncoder.copyLuma(from: frame.capturedImage)
        else { return }

        lastLocalizeAt = elapsed
        requestInFlight = true
        let intrinsics = ImmersalFrameEncoder.scaledIntrinsics(frame.camera.intrinsics)
        let token = ImmersalConfig.token
        let mapIDs = self.mapIDs

        Task { [weak self] in
            let png = await Task.detached(priority: .userInitiated) {
                ImmersalFrameEncoder.grayscalePNG(from: plane)
            }.value
            guard let self else { return }
            guard let png else {
                self.finishRequest(elapsed: elapsed, transform: transform, png: nil,
                                   intrinsics: intrinsics, trackingNormal: trackingNormal,
                                   result: ImmersalLocalizeResult(success: false, error: "encode",
                                                                  mapID: nil, pose: nil,
                                                                  latency: 0, requestBytes: 0))
                return
            }
            let client = ImmersalClient(token: token, mapIDs: mapIDs)
            let result = await client.localize(pngData: png, fx: intrinsics.fx, fy: intrinsics.fy,
                                               ox: intrinsics.ox, oy: intrinsics.oy)
            self.finishRequest(elapsed: elapsed, transform: transform, png: png,
                               intrinsics: intrinsics, trackingNormal: trackingNormal, result: result)
        }
    }

    private func finishRequest(elapsed: TimeInterval,
                               transform: simd_float4x4,
                               png: Data?,
                               intrinsics: (fx: Float, fy: Float, ox: Float, oy: Float),
                               trackingNormal: Bool,
                               result: ImmersalLocalizeResult) {
        requestInFlight = false
        attempts += 1
        lastLatencyMS = Int((result.latency * 1000).rounded())
        lastError = result.success ? nil : result.error
        lastMapID = result.mapID

        var disagreement: Float?
        if result.success, let pose = result.pose {
            successes += 1
            if let previousFix, let previousFixAR {
                disagreement = ImmersalPose.odometryDisagreement(previousFix: previousFix, fix: pose,
                                                                 previousAR: previousFixAR,
                                                                 currentAR: transform)
                lastDisagreement = disagreement
            }
            previousFix = pose
            previousFixAR = transform
            lastFixPosition = SIMD3(pose.px, pose.py, pose.pz)
            // A pair is only worth fitting when both frames are trustworthy at
            // that instant: ARKit tracking normally, and the fix not a blunder.
            if trackingNormal, (disagreement ?? 0) < Self.maxAlignmentDisagreement,
               let poseInMap = ImmersalPose.cameraPoseInMap(pose) {
                alignmentPairs.append(.init(immersal: NavigationGeometry.planarPosition(of: poseInMap),
                                            graph: NavigationGeometry.planarPosition(of: transform)))
            }
        } else if ImmersalClient.isTransportFailure(result.error), let png {
            queue(png: png, elapsed: elapsed, transform: transform, intrinsics: intrinsics)
        }

        guard let log else { return }
        append(ProbeLogRow(event: .localize,
                           elapsed: elapsed,
                           arPosition: position(of: transform),
                           arOrientation: simd_quatf(rotation(of: transform)),
                           immersalSuccess: result.success,
                           immersalError: result.error,
                           immersalMapID: result.mapID,
                           immersalPose: result.pose,
                           immersalLatency: result.latency,
                           immersalRequestBytes: result.requestBytes,
                           odometryDisagreement: disagreement),
               to: log)
    }

    // MARK: - Alignment

    /// A fix whose motion disagrees with ARKit by more than this is not used to
    /// fit the alignment, however plausible it looks on its own.
    static let maxAlignmentDisagreement: Float = 0.5

    /// The rigid transform from Immersal map space into this session's ARKit
    /// frame — which is the graph frame whenever the session relocalized into
    /// the saved world map.
    func fitAlignment() throws -> ImmersalAlignment {
        try ImmersalAlignment.fit(pairs: alignmentPairs, mapIDs: mapIDs)
    }

    // MARK: - Ground truth

    /// "I am physically standing at this place, right now."
    ///
    /// The only ground truth in the whole experiment, so the button that calls
    /// it is the biggest thing on the screen.
    func stamp(placeID: String, name: String) {
        guard state == .running, let log, let startedAt else { return }
        lastStampLabel = name
        append(ProbeLogRow(event: .stamp,
                           elapsed: Date().timeIntervalSince(startedAt),
                           arPosition: lastARPosition,
                           arOrientation: lastAROrientation,
                           placeID: placeID,
                           note: name),
               to: log)
    }

    func marker(_ note: String) {
        guard state == .running, let log, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        lastMarker = (note, elapsed)
        append(ProbeLogRow(event: .marker,
                           elapsed: elapsed,
                           arPosition: lastARPosition,
                           arOrientation: lastAROrientation,
                           note: note),
               to: log)
    }

    // MARK: - Offline queue

    private func queue(png: Data, elapsed: TimeInterval, transform: simd_float4x4,
                       intrinsics: (fx: Float, fy: Float, ox: Float, oy: Float)) {
        guard pending.count < Self.pendingLimit else { return }
        pendingSequence += 1
        let url = pendingDirectory.appendingPathComponent("frame-\(pendingSequence).png")
        guard (try? png.write(to: url, options: [.atomic])) != nil else { return }
        pending.append(PendingFrame(sequence: pendingSequence, elapsed: elapsed,
                                    arTransform: transform,
                                    fx: intrinsics.fx, fy: intrinsics.fy,
                                    ox: intrinsics.ox, oy: intrinsics.oy,
                                    url: url))
        pendingCount = pending.count
    }

    /// Sends everything the network dropped, once there is signal again.
    ///
    /// Accuracy numbers survive a Wi-Fi dead spot this way; latency numbers from
    /// replayed frames are meaningless and are marked `replayed` in the log so
    /// the analysis can exclude them.
    func replayPending() async {
        guard !isReplaying, !ImmersalConfig.token.isEmpty, !mapIDs.isEmpty else { return }
        isReplaying = true
        defer { isReplaying = false }

        let client = ImmersalClient(token: ImmersalConfig.token, mapIDs: mapIDs)
        let queued = pending
        for frame in queued {
            guard let png = try? Data(contentsOf: frame.url) else { continue }
            let result = await client.localize(pngData: png, fx: frame.fx, fy: frame.fy,
                                               ox: frame.ox, oy: frame.oy)
            if ImmersalClient.isTransportFailure(result.error) { break }  // still offline
            if let log {
                append(ProbeLogRow(event: .localize,
                                   elapsed: frame.elapsed,
                                   arPosition: position(of: frame.arTransform),
                                   arOrientation: simd_quatf(rotation(of: frame.arTransform)),
                                   immersalSuccess: result.success,
                                   immersalError: result.error,
                                   immersalMapID: result.mapID,
                                   immersalPose: result.pose,
                                   immersalLatency: result.latency,
                                   immersalRequestBytes: result.requestBytes,
                                   note: "replayed"),
                       to: log)
            }
            try? FileManager.default.removeItem(at: frame.url)
            pending.removeAll { $0.sequence == frame.sequence }
            pendingCount = pending.count
        }
    }

    // MARK: - Private

    private var lastARPosition: SIMD3<Float>?
    private var lastAROrientation: simd_quatf?

    private func append(_ row: ProbeLogRow, to log: ProbeLog) {
        if row.event == .frame || row.event == .localize {
            lastARPosition = row.arPosition
            lastAROrientation = row.arOrientation
        }
        log.append(row)
        rowCount = log.rowCount
    }

    private func position(of transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    private func rotation(of transform: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ))
    }
}
