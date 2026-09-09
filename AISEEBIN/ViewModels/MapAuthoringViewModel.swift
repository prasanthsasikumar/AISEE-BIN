import ARKit
import Foundation
import Observation
import simd

/// One rung of the publish ladder, rendered as a checklist inside the progress
/// card so a mapper who looks away can see exactly where it stopped.
enum AuthoringStep: Int, CaseIterable, Identifiable {
    case capture, archive, upload, publish

    var id: Int { rawValue }

    /// Shown for the step in flight, and for steps not reached yet.
    var activeLabel: String {
        switch self {
        case .capture: return "Capturing world map"
        case .archive: return "Archiving world map"
        case .upload:  return "Uploading"
        case .publish: return "Publishing version record"
        }
    }

    /// Shown once the step is behind us.
    var doneLabel: String {
        switch self {
        case .capture: return "Captured world map"
        case .archive: return "Archived world map"
        case .upload:  return "Uploaded"
        case .publish: return "Published"
        }
    }
}

/// Drives the sighted mapper's authoring screen: marks POIs at the current pose
/// (as `ARAnchor`s plus graph nodes), edits edges, saves the map bundle locally,
/// and publishes it to the server as a new version.
@MainActor
@Observable
final class MapAuthoringViewModel {

    let arManager: ARNavigationManager
    let mapStore: MapStore
    @ObservationIgnored private let sync = MapSyncService()

    private(set) var session: MapAuthoringSession
    private(set) var statusMessage: String?
    private(set) var isBusy = false
    private(set) var hasUnsavedChanges = false
    private(set) var localVersion: LocalMapVersion?
    private(set) var lastPointCount: Int?
    /// Current step of a save/upload, shown as a progress card while `isBusy`.
    private(set) var progressStage: String?
    /// 0…1 when the current step has measurable progress, else `nil` (indeterminate).
    private(set) var progressFraction: Double?
    /// Which rung of the publish ladder is in flight, for the checklist.
    private(set) var progressStep: AuthoringStep?
    /// True only during `upload`, when the full four-step checklist applies.
    private(set) var isUploading = false
    /// "20.3 MB of 31.7 MB" while bytes are moving.
    private(set) var progressBytesText: String?
    /// Server version being written, once the number has been reserved.
    private(set) var progressVersion: Int?
    /// Set when a save/upload fails; the view shows it in an alert.
    var errorMessage: String?
    /// Maps the server holds, for the import picker. Empty until listed.
    private(set) var availableMaps: [RemoteMapSummary] = []
    private(set) var isListingMaps = false
    /// Why the listing failed, shown in the picker instead of an empty list.
    private(set) var mapListError: String?
    /// Breadcrumbs since the last mark, sampled while tracking is reliable.
    private(set) var trail: [SIMD2<Float>] = []
    @ObservationIgnored private var trailTask: Task<Void, Never>?
    /// Minimum distance between breadcrumbs (metres).
    private let trailSpacing: Float = 0.3

    /// Name a map starts with until the mapper renames it when publishing.
    static let defaultMapName = "Greenhouse"

    var mapName: String { session.map.name }
    /// Slug the next publish targets: the one this bundle is already bound to,
    /// or a fresh one derived from the name when nothing has been published yet.
    var targetSlug: String { localVersion?.slug ?? ServerConfig.slug(from: session.map.name) }

    var nodes: [NavigationPOI] { session.map.pois }
    var edges: [NavigationEdge] { session.map.edges }
    var chainFromID: String? { session.lastAddedID }
    var mappingStatus: ARFrame.WorldMappingStatus { arManager.worldMappingStatus }
    var canMark: Bool { arManager.localizationStatus.isReliable }
    /// Mapping status is advisory: ARKit flickers between limited/extending in
    /// sparse rooms, so we let ARKit itself decide whether a map can be captured.
    var canSave: Bool { !nodes.isEmpty && !isBusy }
    /// Whether the progress card belongs on screen. Any job that sets a stage
    /// qualifies, not just publishing: an import downloads tens of megabytes and
    /// looks frozen without a bar.
    var showsProgress: Bool { progressStage != nil || isUploading }
    var canUpload: Bool { canSave }
    var mappingWarning: String? {
        mappingStatus.isSaveable ? nil : "Mapping is still \(mappingStatus.label); keep scanning for a more reliable map."
    }

    init(arManager: ARNavigationManager, mapStore: MapStore) {
        self.arManager = arManager
        self.mapStore = mapStore
        localVersion = mapStore.loadVersion()
        if let existing = mapStore.loadMap() {
            session = MapAuthoringSession(map: existing)
        } else {
            session = MapAuthoringSession(mapName: Self.defaultMapName)
        }
        startTrailRecording()
    }

    deinit {
        trailTask?.cancel()
    }

    // MARK: - Breadcrumb trail

    /// Samples the camera position at 5 Hz. Only trusted poses are recorded, and
    /// only when the user has moved on by `trailSpacing`.
    private func startTrailRecording() {
        trailTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                guard arManager.localizationStatus.isReliable else { continue }
                let position = NavigationGeometry.planarPosition(of: arManager.cameraTransform)
                if let last = trail.last, simd_distance(last, position) < trailSpacing { continue }
                trail.append(position)
            }
        }
    }

    private func resetTrail() {
        trail.removeAll()
    }

    // MARK: - Naming

    /// Renames the map. The web editor lists maps by this name, so it is what a
    /// mapper sees there. The slug stays put once published, keeping history
    /// under one map; a name set before the first publish picks the slug.
    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.map.name else { return }
        session.rename(to: trimmed)
        hasUnsavedChanges = true
    }

    // MARK: - Scanning

    /// Discards the local bundle and begins a new scan from here. Server
    /// versions are untouched until you upload.
    func startFreshScan() {
        // A fresh scan is a new map, but it keeps the name the mapper chose;
        // only the geometry starts over.
        session = MapAuthoringSession(mapName: session.map.name)
        try? mapStore.deleteAll()
        try? arManager.deleteSavedWorldMap()
        localVersion = nil
        arManager.start(relocalize: false)
        hasUnsavedChanges = false
        resetTrail()
        statusMessage = "Fresh scan started. Walk slowly and sweep the camera across foliage and fixtures."
    }

    /// Restarts tracking against the saved world map so new nodes can be added
    /// to an existing scan.
    func continueExistingScan() {
        arManager.start(relocalize: true)
        statusMessage = "Relocalizing against the saved map. Wait for Tracking Ready before marking."
    }

    // MARK: - Editing

    func markHere(name: String, category: POICategory, details: String?) {
        let transform = arManager.cameraTransform
        let position = NavigationGeometry.planarPosition(of: transform)
        let before = session.map.pois.count
        let poi = session.addNode(name: name, category: category, details: details, position: position, trail: trail)
        let waypoints = session.map.pois.count - before - 1
        arManager.addPOIAnchor(id: poi.id, transform: transform)
        resetTrail()
        hasUnsavedChanges = true
        let suffix = waypoints > 0 ? " Added \(waypoints) waypoint\(waypoints == 1 ? "" : "s") along the walked path." : ""
        statusMessage = "Marked \(poi.name) at x \(String(format: "%.1f", position.x)), z \(String(format: "%.1f", position.y)).\(suffix)"
    }

    func update(_ id: String, name: String, category: POICategory, details: String?) {
        session.updateNode(id, name: name, category: category, details: details)
        hasUnsavedChanges = true
    }

    func connect(_ a: String, to b: String) {
        session.connect(a, to: b)
        hasUnsavedChanges = true
    }

    func continueChain(from id: String) {
        session.continueChain(from: id)
        resetTrail()
        statusMessage = "Next mark links from \(session.map.pois.first { $0.id == id }?.name ?? id)."
    }

    func remove(_ id: String) {
        session.removeNode(id)
        arManager.removePOIAnchor(id: id)
        hasUnsavedChanges = true
    }

    /// Edges touching a node, as the *other* node's display name.
    func neighbours(of id: String) -> [String] {
        edges.compactMap { edge in
            let other = edge.from == id ? edge.to : (edge.to == id ? edge.from : nil)
            return other.flatMap { o in nodes.first { $0.id == o }?.name }
        }
    }

    // MARK: - Saving & publishing

    /// Captures the world map, writes world map + point cloud + graph locally.
    @discardableResult
    func saveLocally() async -> (worldMap: Data, points: Data)? {
        guard !nodes.isEmpty else {
            errorMessage = "Mark at least one node before saving."
            return nil
        }
        isBusy = true
        defer { isBusy = false; progressStage = nil; progressStep = nil }
        do {
            log("save: capturing world map (mapping=\(mappingStatus.label), tracking=\(arManager.localizationStatus.label))")
            progressStep = .capture
            progressStage = "Capturing world map…"
            let map = try await arManager.captureWorldMap()
            let pointCount = map.rawFeaturePoints.points.count
            log("save: captured, \(pointCount) feature points, \(map.anchors.count) anchors")

            progressStep = .archive
            progressStage = "Archiving world map…"
            let worldMapData = try arManager.archive(map)
            log("save: archived \(worldMapData.count) bytes")

            progressStage = "Writing files…"
            let points = PointCloudCodec.encode(map.rawFeaturePoints.points)
            try mapStore.saveWorldMapData(worldMapData)
            try mapStore.savePointCloud(points)
            try mapStore.saveMap(session.map)
            arManager.noteWorldMapReplaced()
            lastPointCount = pointCount
            hasUnsavedChanges = false
            statusMessage = "Saved \(nodes.count) nodes, \(edges.count) edges and \(pointCount) feature points (\(Self.format(worldMapData.count)))."
            log("save: done")
            return (worldMapData, points)
        } catch {
            log("save FAILED: \(error)")
            errorMessage = "Could not capture the world map: \(error.localizedDescription)\n\nKeep scanning with slow sweeps until mapping reads ‘extending’ or ‘mapped’, then try again."
            statusMessage = "Save failed."
            return nil
        }
    }

    /// Saves locally, then publishes everything as a new server version.
    func upload(name: String, note: String?) async {
        rename(to: name)
        isUploading = true
        defer { isUploading = false }
        guard let bundle = await saveLocally() else { return }
        isBusy = true
        defer {
            isBusy = false
            progressStage = nil
            progressFraction = nil
            progressStep = nil
            progressBytesText = nil
            progressVersion = nil
        }
        progressStep = .upload
        progressStage = "Uploading world map (\(Self.format(bundle.worldMap.count)))…"
        progressFraction = 0
        log("upload: starting, worldmap=\(bundle.worldMap.count) bytes, points=\(bundle.points.count) bytes")
        do {
            let saved = try await sync.upload(graph: session.map,
                                              worldMap: bundle.worldMap,
                                              pointCloud: bundle.points,
                                              pointCount: lastPointCount ?? 0,
                                              note: note,
                                              slug: targetSlug) { [weak self] progress in
                guard let self else { return }
                if progress.stage != progressStage { log("upload: \(progress.stage)") }
                progressStage = progress.stage
                progressFraction = progress.fraction
                progressStep = progress.stage.hasPrefix("Publishing") ? .publish : .upload
                progressBytesText = progress.bytesText
                progressVersion = progress.version
            }
            let record = LocalMapVersion(version: saved.version, source: .ios,
                                         updatedAt: Date(), slug: saved.mapSlug)
            try mapStore.saveVersion(record)
            localVersion = record
            statusMessage = "Published “\(session.map.name)” as version \(saved.version). Fine-tune it at \(ServerConfig.editorURL.host ?? "the web editor")."
            log("upload: done, version \(saved.version)")
        } catch {
            log("upload FAILED: \(error)")
            errorMessage = "Upload failed: \(error.localizedDescription)"
            statusMessage = "Upload failed."
        }
    }

    private func log(_ message: String) {
        print("[AISEE authoring] \(message)")
    }

    private static func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Lists the maps on the server for the import picker. Cheap enough to redo
    /// every time the sheet opens, so a map published elsewhere shows up.
    func loadAvailableMaps() async {
        isListingMaps = true
        mapListError = nil
        defer { isListingMaps = false }
        do {
            availableMaps = try await sync.availableMaps()
            log("picker: \(availableMaps.count) maps on server")
        } catch {
            log("picker FAILED: \(error)")
            mapListError = error.localizedDescription
        }
    }

    /// Pulls the newest server version (graph + world map + points) into the
    /// local bundle and relocalizes against it, so it can be extended here.
    func importLatestFromServer(slug: String? = nil) async {
        let wanted = slug ?? targetSlug
        isBusy = true
        defer { isBusy = false }
        statusMessage = nil
        progressStage = "Fetching latest version…"
        progressFraction = nil
        progressBytesText = nil
        defer { progressStage = nil; progressFraction = nil; progressBytesText = nil }
        log("import: fetching latest version of \(wanted)")
        do {
            guard let remote = try await sync.latestVersion(slug: wanted) else {
                let asked = availableMaps.first { $0.slug == wanted }?.name ?? wanted
                statusMessage = "The server has no versions of “\(asked)” yet."
                return
            }
            log("import: latest is v\(remote.version) (\(remote.source.rawValue)), worldmap=\(remote.worldmapPath ?? "nil"), points=\(remote.pointcloudPath ?? "nil")")
            if let path = remote.worldmapPath {
                progressStage = "Downloading world map v\(remote.version)…"
                try mapStore.saveWorldMapData(try await sync.download(path: path) { [weak self] p in
                    self?.progressFraction = p.fraction * 0.9
                    self?.progressBytesText = p.bytesText
                    if Int(p.fraction * 100) % 25 == 0 { self?.log("import: world map \(Int(p.fraction * 100))%") }
                })
            }
            if let path = remote.pointcloudPath {
                progressStage = "Downloading point cloud…"
                progressBytesText = nil
                try mapStore.savePointCloud(try await sync.download(path: path) { [weak self] p in
                    self?.progressFraction = 0.9 + p.fraction * 0.1
                    self?.progressBytesText = p.bytesText
                })
            }
            progressFraction = 1
            log("import: downloads done, writing graph with \(remote.graph.pois.count) nodes")
            try mapStore.saveMap(remote.graph)
            let record = LocalMapVersion(version: remote.version, source: remote.source,
                                         updatedAt: Date(), slug: remote.mapSlug)
            try mapStore.saveVersion(record)
            localVersion = record
            session = MapAuthoringSession(map: remote.graph)
            hasUnsavedChanges = false
            arManager.noteWorldMapReplaced()
            arManager.start(relocalize: true)
            statusMessage = "Imported version \(remote.version) (\(remote.source.rawValue)). Relocalizing…"
            log("import: done")
        } catch {
            log("import FAILED: \(error)")
            errorMessage = "Import failed: \(error.localizedDescription)"
            statusMessage = "Import failed."
        }
    }
}
