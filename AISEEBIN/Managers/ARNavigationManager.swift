import ARKit
import Foundation
import Observation
import simd

/// One estimate of where the visitor is, in the graph frame, handed to the
/// view model. ARKit produces one per camera frame (extracted on the main queue
/// inside the delegate callback so that no `ARFrame` is retained); glasses
/// positioning produces one per tick of its extrapolator.
struct PoseSnapshot {
    let cameraTransform: simd_float4x4
    let timestamp: TimeInterval
    let trackingReliable: Bool
    let featurePointCount: Int
}

/// User-facing summary of `ARCamera.TrackingState`, plus whether we trust the pose.
enum LocalizationStatus: Equatable {
    case unsupported
    case notStarted
    case initializing
    case relocalizing
    case limited(reason: String)
    case trackingReady

    var label: String {
        switch self {
        case .unsupported:          return "ARKit not supported"
        case .notStarted:           return "Not started"
        case .initializing:         return "Initializing…"
        case .relocalizing:         return "Relocalizing…"
        case .limited(let reason):  return "Limited: \(reason)"
        case .trackingReady:        return "Tracking Ready"
        }
    }

    /// Only `.trackingReady` poses are good enough to drive guidance.
    var isReliable: Bool { self == .trackingReady }
}

/// Owns the `ARSession`, reports tracking quality, exposes the live camera pose,
/// and persists / restores an `ARWorldMap` so the app can relocalize inside a
/// previously scanned greenhouse.
///
/// All state is main-actor isolated. ARKit calls the delegate on the main queue
/// because `session.delegateQueue` is left `nil`, so the `nonisolated` delegate
/// entry points hop back in with `MainActor.assumeIsolated`.
@MainActor
@Observable
final class ARNavigationManager: NSObject, ARSessionDelegate {

    // MARK: Observable state

    private(set) var localizationStatus: LocalizationStatus = .notStarted
    private(set) var trackingStateDescription = "n/a"
    private(set) var featurePointCount = 0
    private(set) var cameraTransform = matrix_identity_float4x4
    private(set) var framesPerSecond: Double = 0
    private(set) var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    private(set) var hasSavedWorldMap = false
    /// `true` once a saved map was handed to the session; tracking reaches
    /// `.trackingReady` only after ARKit has matched the environment to it.
    private(set) var isUsingSavedWorldMap = false
    private(set) var lastErrorMessage: String?
    /// Planar positions of every `poi:<id>` anchor ARKit currently knows about.
    /// Populated from the saved world map after relocalization, and by
    /// `addPOIAnchor` during authoring.
    private(set) var poiAnchorPositions: [String: SIMD2<Float>] = [:]

    // MARK: Session

    let session = ARSession()

    /// Called on the main actor for every camera frame.
    @ObservationIgnored var onFrame: ((PoseSnapshot) -> Void)?
    /// Called on the main actor whenever the set of POI anchors changes.
    @ObservationIgnored var onPOIAnchorsChanged: (([String: SIMD2<Float>]) -> Void)?

    /// THROWAWAY, for the Immersal comparison harness in `Probe/` only.
    ///
    /// `PoseSnapshot` deliberately drops the pixel buffer and the intrinsics
    /// so that no `ARFrame` is retained; the harness needs both to ask a VPS
    /// where it is, so it gets the frame itself and must copy what it wants
    /// synchronously. Nil unless a measurement walk is running. Delete
    /// alongside `Probe/`.
    @ObservationIgnored var onProbeFrame: ((ARFrame, ARCamera.TrackingState) -> Void)?

    static let poiAnchorPrefix = "poi:"

    @ObservationIgnored private var fpsWindowStart: TimeInterval = 0
    @ObservationIgnored private var fpsFrameCount = 0
    @ObservationIgnored private var trackingReliable = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    /// Location of the persisted world map (shared with `MapStore`).
    let worldMapURL: URL

    init(mapStore: MapStore = MapStore()) {
        worldMapURL = mapStore.worldMapURL
        super.init()
        session.delegate = self
        hasSavedWorldMap = FileManager.default.fileExists(atPath: worldMapURL.path)
        if !Self.isSupported { localizationStatus = .unsupported }
    }

    // MARK: - Lifecycle

    /// Starts (or restarts) world tracking. When a saved map exists and
    /// `relocalize` is true, ARKit is asked to relocalize against it.
    func start(relocalize: Bool = true) {
        guard Self.isSupported else {
            localizationStatus = .unsupported
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        configuration.isAutoFocusEnabled = true

        isUsingSavedWorldMap = false
        if relocalize, let map = try? loadWorldMap() {
            configuration.initialWorldMap = map
            isUsingSavedWorldMap = true
        }

        lastErrorMessage = nil
        trackingReliable = false
        poiAnchorPositions = [:]   // anchors from `initialWorldMap` arrive again via didAdd
        localizationStatus = isUsingSavedWorldMap ? .relocalizing : .initializing
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - POI anchors

    /// Drops (or replaces) a named anchor for a POI at the given pose. Anchors
    /// are persisted inside the world map, so their positions relocalize with it.
    func addPOIAnchor(id: String, transform: simd_float4x4) {
        removePOIAnchor(id: id)
        session.add(anchor: ARAnchor(name: Self.poiAnchorPrefix + id, transform: transform))
    }

    func removePOIAnchor(id: String) {
        let name = Self.poiAnchorPrefix + id
        for anchor in session.currentFrame?.anchors ?? [] where anchor.name == name {
            session.remove(anchor: anchor)
        }
    }

    func pause() {
        session.pause()
        localizationStatus = .notStarted
    }

    // MARK: - World map persistence

    /// Asks ARKit for the current world map. Best results when
    /// `worldMappingStatus` is `.mapped`.
    func captureWorldMap() async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                if let map {
                    continuation.resume(returning: map)
                } else {
                    continuation.resume(throwing: error ?? ARNavigationError.worldMapUnavailable)
                }
            }
        }
    }

    /// Secure-coded archive suitable for disk or upload.
    func archive(_ map: ARWorldMap) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
    }

    /// Captures the current world map and writes it atomically to `worldMapURL`.
    @discardableResult
    func saveWorldMap() async throws -> ARWorldMap {
        let map = try await captureWorldMap()
        try archive(map).write(to: worldMapURL, options: [.atomic])
        hasSavedWorldMap = true
        return map
    }

    /// Call after a world map file has been written by someone else (server download).
    func noteWorldMapReplaced() {
        hasSavedWorldMap = FileManager.default.fileExists(atPath: worldMapURL.path)
    }

    /// Reads and unarchives the persisted world map.
    func loadWorldMap() throws -> ARWorldMap {
        let data = try Data(contentsOf: worldMapURL)
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw ARNavigationError.worldMapCorrupt
        }
        return map
    }

    func deleteSavedWorldMap() throws {
        if FileManager.default.fileExists(atPath: worldMapURL.path) {
            try FileManager.default.removeItem(at: worldMapURL)
        }
        hasSavedWorldMap = false
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated {
            handle(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        MainActor.assumeIsolated {
            apply(trackingState: camera.trackingState)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            lastErrorMessage = error.localizedDescription
            localizationStatus = .limited(reason: "Session error")
            trackingReliable = false
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            localizationStatus = .limited(reason: "Interrupted")
            trackingReliable = false
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            localizationStatus = .relocalizing
        }
    }

    /// Ask ARKit to recover the previous coordinate frame after an interruption
    /// (phone call, app switch) instead of starting a fresh one.
    nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated { apply(anchors: anchors, removed: false) }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated { apply(anchors: anchors, removed: false) }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated { apply(anchors: anchors, removed: true) }
    }

    // MARK: - Private

    private func apply(anchors: [ARAnchor], removed: Bool) {
        var changed = false
        for anchor in anchors {
            guard let name = anchor.name, name.hasPrefix(Self.poiAnchorPrefix) else { continue }
            let id = String(name.dropFirst(Self.poiAnchorPrefix.count))
            if removed {
                changed = poiAnchorPositions.removeValue(forKey: id) != nil || changed
            } else {
                let position = NavigationGeometry.planarPosition(of: anchor.transform)
                if poiAnchorPositions[id] != position {
                    poiAnchorPositions[id] = position
                    changed = true
                }
            }
        }
        if changed { onPOIAnchorsChanged?(poiAnchorPositions) }
    }

    private func handle(frame: ARFrame) {
        cameraTransform = frame.camera.transform
        worldMappingStatus = frame.worldMappingStatus
        featurePointCount = frame.rawFeaturePoints?.points.count ?? 0
        updateFPS(timestamp: frame.timestamp)

        onFrame?(PoseSnapshot(cameraTransform: frame.camera.transform,
                                 timestamp: frame.timestamp,
                                 trackingReliable: trackingReliable,
                                 featurePointCount: featurePointCount))

        onProbeFrame?(frame, frame.camera.trackingState)
    }

    private func updateFPS(timestamp: TimeInterval) {
        fpsFrameCount += 1
        let elapsed = timestamp - fpsWindowStart
        if elapsed >= 1 {
            framesPerSecond = Double(fpsFrameCount) / elapsed
            fpsFrameCount = 0
            fpsWindowStart = timestamp
        }
    }

    private func apply(trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .notAvailable:
            trackingStateDescription = "notAvailable"
            localizationStatus = .initializing
            trackingReliable = false
        case .limited(let reason):
            trackingReliable = false
            switch reason {
            case .initializing:
                trackingStateDescription = "limited.initializing"
                localizationStatus = .initializing
            case .relocalizing:
                trackingStateDescription = "limited.relocalizing"
                localizationStatus = .relocalizing
            case .excessiveMotion:
                trackingStateDescription = "limited.excessiveMotion"
                localizationStatus = .limited(reason: "Moving too fast")
            case .insufficientFeatures:
                trackingStateDescription = "limited.insufficientFeatures"
                localizationStatus = .limited(reason: "Not enough visual detail")
            @unknown default:
                trackingStateDescription = "limited.unknown"
                localizationStatus = .limited(reason: "Limited tracking")
            }
        case .normal:
            trackingStateDescription = "normal"
            localizationStatus = .trackingReady
            trackingReliable = true
        }
    }
}

enum ARNavigationError: LocalizedError {
    case worldMapUnavailable
    case worldMapCorrupt

    var errorDescription: String? {
        switch self {
        case .worldMapUnavailable: return "ARKit could not produce a world map yet. Scan more of the space and try again."
        case .worldMapCorrupt:     return "The saved world map could not be read."
        }
    }
}
