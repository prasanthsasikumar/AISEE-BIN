import ARKit
import Foundation
import Observation
import simd

/// Snapshot of internals for the on-screen debug visualizer.
struct DebugInfo {
    var fps: Double = 0
    var trackingState = "n/a"
    var featurePoints = 0
    var worldMapping = "n/a"
    var position = SIMD2<Float>(0, 0)
    var headingDegrees: Float = 0
    var subGoal = "—"
    var routeNodes: [String] = []
    var anchoredNodes = 0
}

/// Which half of the app is active. Authoring is for the sighted mapper.
/// Which camera is telling the app where the visitor is.
enum PositioningSource: Equatable {
    /// ARKit on the chest-mounted phone, relocalized into the saved world map.
    case phone
    /// Immersal fixes on the AiSee glasses' video, the phone in a pocket.
    case glasses
}

enum AppMode: String, CaseIterable, Identifiable {
    case navigation = "Navigate"
    case authoring = "Author"
    var id: String { rawValue }
}

/// Server synchronisation state shown in the status area.
enum MapSyncState: Equatable {
    case idle
    case checking
    case upToDate(Int)
    case downloading(Int)
    case updated(Int)
    case failed(String)
    case offlineSample

    var label: String {
        switch self {
        case .idle:                 return ""
        case .checking:             return "Checking server for map updates…"
        case .upToDate(let v):      return "Map v\(v) (latest)"
        case .downloading(let v):   return "Downloading map v\(v)…"
        case .updated(let v):       return "Updated to map v\(v)"
        case .failed(let message):  return "Sync failed: \(message)"
        case .offlineSample:        return "No map on server yet, using bundled sample"
        }
    }
}

/// Orchestrates one navigation session: takes camera poses from
/// `ARNavigationManager`, follows the route with `RouteTracker`, asks
/// `GuidancePolicy` whether to speak, hands cues to `GuidanceManager`, and
/// answers voice commands from the push-to-talk button, Siri, or the Action Button.
@MainActor
@Observable
final class NavigationViewModel {

    // MARK: Dependencies

    let arManager: ARNavigationManager
    let guidance: GuidanceManager
    let recognizer: VoiceCommandRecognizer
    let mapStore: MapStore
    let glasses: GlassesService
    let glassesPositioning: GlassesPositioning
    @ObservationIgnored private let sync = MapSyncService()
    @ObservationIgnored private let thresholds: GuidanceThresholds

    /// Rebuilt whenever the map or its anchors change.
    private(set) var engine: PathfindingEngine
    @ObservationIgnored private var baseMap: NavigationMap
    @ObservationIgnored private var commandParser: CommandParser
    @ObservationIgnored private var proximityAnnouncer: ProximityAnnouncer

    // MARK: Route state

    @ObservationIgnored private var tracker: RouteTracker?
    @ObservationIgnored private var policy: GuidancePolicy
    @ObservationIgnored private var lastInstruction: NavigationInstruction?
    @ObservationIgnored private var pendingDestinationID: String?
    @ObservationIgnored private var unknownCommandCount = 0

    // MARK: UI state

    var selectedDestination: NavigationPOI?
    private(set) var isNavigating = false
    private(set) var hasArrived = false
    private(set) var isOffRoute = false
    private(set) var currentInstruction: NavigationInstruction?
    private(set) var remainingDistance: Float = 0
    private(set) var statusMessage: String?
    private(set) var debug = DebugInfo()
    var showDebug = false
    var mode: AppMode = .navigation {
        didSet { if mode != oldValue { didChange(mode: mode) } }
    }
    var positioningSource: PositioningSource = .phone {
        didSet { if positioningSource != oldValue { didChange(positioningSource: positioningSource) } }
    }
    private(set) var syncState: MapSyncState = .idle
    /// 0…1 while `syncState` is `.downloading`.
    private(set) var syncProgress: Double = 0
    /// "28.4 MB of 76.8 MB" while downloading, else `nil`.
    private(set) var syncBytesText: String?
    private(set) var localVersion: LocalMapVersion?
    /// 1-based leg of the active route and its total, for "Leg 2 of 4".
    private(set) var routeLeg = 0
    private(set) var routeLegCount = 0
    /// Name of the place last arrived at, kept so the arrival panel can stay up.
    private(set) var arrivedPlaceName: String?

    var isAuthoring: Bool { mode == .authoring }

    var destinations: [NavigationPOI] { engine.destinations }
    var localizationStatus: LocalizationStatus {
        positioningSource == .glasses ? glassesPositioning.localizationStatus : arManager.localizationStatus
    }
    /// The visitor's camera pose in the graph frame, whichever camera it came from.
    var currentTransform: simd_float4x4 {
        positioningSource == .glasses ? glassesPositioning.cameraTransform : arManager.cameraTransform
    }
    var mapAlignment: ImmersalAlignment? { baseMap.immersalAlignment }

    /// Why the glasses cannot take over positioning right now, or `nil`.
    var glassesBlockedReason: String? {
        if !glasses.isConnected { return "Connect the glasses first." }
        if mapAlignment == nil { return "The glasses show their view but cannot position you until this map has an Immersal alignment: run a probe walk with the phone and save one." }
        if !ImmersalConfig.isConfigured { return ImmersalConfig.missingCredentialsHint }
        return nil
    }
    var isListening: Bool { recognizer.isListening }
    var mapName: String { baseMap.name }
    var usesAuthoredMap: Bool { mapStore.hasSavedMap }

    /// Navigation can start once tracking is reliable; with a saved map that
    /// means ARKit has relocalized into the greenhouse's coordinate frame.
    var canStartNavigation: Bool {
        selectedDestination != nil && localizationStatus.isReliable && !isNavigating
    }

    /// "between the Window and the Main Entrance, about 7 m from the Window" —
    /// shown while off route so a helper can place the visitor at a glance.
    var lastKnownDescription: String? {
        let transform = currentTransform
        return LocationDescriber(map: engine.map)
            .describe(position: NavigationGeometry.planarPosition(of: transform),
                      heading: NavigationGeometry.heading(of: transform))?
            .screenText
    }

    /// Managers are optional so callers (tests, previews) can inject fakes; default
    /// argument expressions run outside the main actor, so the real ones are
    /// created here instead.
    init(map: NavigationMap? = nil,
         thresholds: GuidanceThresholds = GuidanceThresholds(),
         mapStore: MapStore = MapStore(),
         arManager: ARNavigationManager? = nil,
         guidance: GuidanceManager? = nil,
         recognizer: VoiceCommandRecognizer? = nil,
         glasses: GlassesService? = nil,
         glassesPositioning: GlassesPositioning? = nil) {
        self.thresholds = thresholds
        self.mapStore = mapStore
        self.arManager = arManager ?? ARNavigationManager(mapStore: mapStore)
        self.guidance = guidance ?? GuidanceManager()
        self.recognizer = recognizer ?? VoiceCommandRecognizer()
        self.glasses = glasses ?? GlassesService()
        self.glassesPositioning = glassesPositioning ?? GlassesPositioning()
        self.policy = GuidancePolicy(thresholds: thresholds)

        let initialMap = map ?? mapStore.loadMap() ?? SampleGreenhouseMap.map
        self.baseMap = initialMap
        self.engine = PathfindingEngine(map: initialMap)
        self.commandParser = CommandParser(pois: initialMap.pois)
        self.proximityAnnouncer = ProximityAnnouncer(pois: initialMap.pois)
        self.localVersion = mapStore.loadVersion()

        // `-startMode author` launch argument opens straight into Authoring (used for screenshots and QA).
        if UserDefaults.standard.string(forKey: "startMode") == "author" {
            self.mode = .authoring
        }
    }

    // MARK: - Session lifecycle

    func startSession() {
        arManager.onFrame = { [weak self] snapshot in self?.handle(snapshot) }
        arManager.onPOIAnchorsChanged = { [weak self] positions in self?.applyAnchors(positions) }
        glassesPositioning.onPose = { [weak self] snapshot in self?.handle(snapshot) }
        glasses.onFrame = { [weak positioning = glassesPositioning] frame in positioning?.consume(frame) }
        glasses.onKeyPress = { [weak self] action in self?.handle(keyAction: action) }
        recognizer.onFinalTranscript = { [weak self] text in self?.handle(transcript: text) }
        recognizer.onDidStopListening = { [weak self] in self?.closeGlassesMicrophone() }
        AppCommandBus.shared.handler = { [weak self] command in self?.handle(appCommand: command) }

        startPositioning()
        observeGlassesConnection()
        glasses.connectAutomatically()
        Task { _ = await recognizer.requestAuthorization() }
        Task { await checkForMapUpdate() }
    }

    /// Starts whichever camera is positioning the visitor and says what to do
    /// while it finds the map.
    private func startPositioning() {
        switch positioningSource {
        case .phone:
            glassesPositioning.stop()
            glasses.keepStreaming = false
            arManager.start(relocalize: true)
            if arManager.isUsingSavedWorldMap {
                guidance.speak("Relocalizing. Please look around slowly.", interrupt: true)
            }
        case .glasses:
            arManager.pause()
            glassesPositioning.start(alignment: baseMap.immersalAlignment)
            glasses.keepStreaming = true
            Task { [glasses, guidance] in
                do {
                    try await glasses.startStreaming()
                } catch {
                    guidance.speak("The glasses camera did not start. \(error.localizedDescription)", interrupt: true)
                }
            }
            guidance.speak("Using the glasses. Please look around slowly.", interrupt: true)
        }
    }

    /// Follows the glasses: connected means they are on the visitor's face and
    /// the phone is going into a pocket, so they take over positioning and the
    /// glasses feed replaces the phone camera; disconnected hands it back.
    /// The switch in `GlassesView` still overrides either way.
    private func observeGlassesConnection() {
        withObservationTracking {
            _ = glasses.isConnected
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.glasses.isConnected, self.positioningSource == .phone {
                    self.positioningSource = .glasses
                } else if !self.glasses.isConnected, self.positioningSource == .glasses {
                    self.guidance.speak("Glasses disconnected. Using the phone camera.", interrupt: true)
                    self.positioningSource = .phone
                }
                self.observeGlassesConnection()
            }
        }
    }

    private func didChange(positioningSource source: PositioningSource) {
        stopNavigation()
        pendingDestinationID = nil
        statusMessage = nil
        startPositioning()
    }

    /// The temple button on the glasses.
    private func handle(keyAction: GlassesService.KeyAction) {
        switch keyAction {
        case .talk:         toggleListening()
        case .whereAmI:     handle(command: .whereAmI)
        case .stopGuidance: handle(command: .stop)
        }
    }

    // MARK: - Server sync

    /// Fetches the newest map version from the server and installs it when it
    /// is newer than the local bundle. Silent when offline.
    func checkForMapUpdate() async {
        syncState = .checking
        do {
            guard let remote = try await sync.latestVersion(slug: localVersion?.slug ?? ServerConfig.mapSlug) else {
                syncState = mapStore.hasSavedMap ? .upToDate(localVersion?.version ?? 0) : .offlineSample
                return
            }
            guard MapSyncService.shouldDownload(remoteVersion: remote.version, local: localVersion) else {
                syncState = .upToDate(remote.version)
                return
            }
            syncState = .downloading(remote.version)
            print("[AISEE sync] installing v\(remote.version) (\(remote.source.rawValue)); local=\(localVersion?.version ?? 0), hasWorldMap=\(mapStore.hasSavedWorldMap)")
            try await install(remote)
            syncState = .updated(remote.version)
            guidance.speak("Map updated to version \(remote.version).", interrupt: false)
        } catch {
            print("[AISEE sync] FAILED: \(error)")
            syncState = .failed(error.localizedDescription)
        }
    }

    private func install(_ remote: RemoteMapVersion) async throws {
        // The world map only changes on iOS uploads; web edits reuse the same file.
        syncProgress = 0
        syncBytesText = nil
        defer { syncBytesText = nil }
        if let path = remote.worldmapPath {
            let needsWorldMap = !mapStore.hasSavedWorldMap || remote.source == .ios || localVersion == nil
            if needsWorldMap {
                try mapStore.saveWorldMapData(try await sync.download(path: path) { [weak self] p in
                    self?.syncProgress = p.fraction * 0.9
                    self?.syncBytesText = p.bytesText
                })
            }
        }
        syncProgress = 0.9
        if let path = remote.pointcloudPath, remote.source == .ios || mapStore.loadPointCloud() == nil {
            try mapStore.savePointCloud(try await sync.download(path: path) { [weak self] p in
                self?.syncProgress = 0.9 + p.fraction * 0.1
            })
        }
        syncProgress = 1
        try mapStore.saveMap(remote.graph)
        let record = LocalMapVersion(version: remote.version, source: remote.source,
                                     updatedAt: Date(), slug: remote.mapSlug)
        try mapStore.saveVersion(record)
        localVersion = record
        arManager.noteWorldMapReplaced()
        reloadMapAndRestart()
    }

    func stopSession() {
        stopNavigation()
        arManager.pause()
        glassesPositioning.stop()
    }

    /// Re-reads the saved map without restarting tracking: the probe screen
    /// may have stored an alignment, which glasses positioning picks up here.
    func reloadMapKeepingSession() {
        baseMap = mapStore.loadMap() ?? SampleGreenhouseMap.map
        localVersion = mapStore.loadVersion()
        rebuildEngine()
        if positioningSource == .glasses {
            glassesPositioning.start(alignment: baseMap.immersalAlignment)
        }
    }

    /// Re-reads the saved map after the authoring screen closes and restarts
    /// tracking against the (possibly new) world map.
    func reloadMapAndRestart() {
        stopNavigation()
        selectedDestination = nil
        baseMap = mapStore.loadMap() ?? SampleGreenhouseMap.map
        localVersion = mapStore.loadVersion()
        rebuildEngine()
        startPositioning()
    }

    // MARK: - Navigation

    func startNavigation() {
        guard let destination = selectedDestination else { return }
        let position = NavigationGeometry.planarPosition(of: currentTransform)
        guard let start = localizationStatus.isReliable ? engine.nearestNode(to: position) : nil else {
            statusMessage = "Wait for tracking before starting."
            return
        }

        let path = engine.findPath(from: engine.name(of: start), to: destination.id)
        guard !path.isEmpty else {
            // Distinguish "the map is broken" from "you are standing somewhere odd".
            let destinationConnected = engine.map.edges.contains { $0.from == destination.id || $0.to == destination.id }
            let startName = engine.displayName(of: start)
            let reason = destinationConnected
                ? "You are nearest the \(startName), which is not connected to the \(destination.name) on this map."
                : "The \(destination.name) is not connected to any path on this map."
            statusMessage = "No route to \(destination.name). \(reason)"
            guidance.speak("I could not find a route to the \(destination.name). \(reason) Please connect it in the map editor.", interrupt: true)
            return
        }

        tracker = RouteTracker(path: path, thresholds: thresholds)
        policy.reset()
        isNavigating = true
        hasArrived = false
        arrivedPlaceName = nil
        isOffRoute = false
        routeLeg = 1
        routeLegCount = path.count
        lastInstruction = nil
        debug.routeNodes = path.map(engine.displayName(of:))
        statusMessage = nil

        if let instruction = makeInstruction(from: currentTransform) {
            currentInstruction = instruction
            lastInstruction = instruction
            guidance.speak("Starting route to the \(destination.name). \(instruction.spokenText)", interrupt: true)
        } else {
            finishNavigation(at: destination.name)
        }
    }

    func stopNavigation() {
        guard isNavigating else { return }
        isNavigating = false
        tracker = nil
        currentInstruction = nil
        remainingDistance = 0
        isOffRoute = false
        routeLeg = 0
        routeLegCount = 0
        debug.subGoal = "—"
        debug.routeNodes = []
        guidance.stopSpeaking()
    }

    // MARK: - World map

    func resetSession(discardSavedMap: Bool) {
        stopNavigation()
        if discardSavedMap {
            try? mapStore.deleteAll()
            try? arManager.deleteSavedWorldMap()
            baseMap = SampleGreenhouseMap.map
            localVersion = nil
            rebuildEngine()
        }
        if positioningSource == .glasses {
            startPositioning()
        } else {
            arManager.start(relocalize: !discardSavedMap)
        }
    }

    // MARK: - Voice

    /// Push-to-talk entry point (button, Action Button, Siri "listen").
    func toggleListening() {
        if recognizer.isListening {
            recognizer.stopListening(deliver: true)
            return
        }
        Task {
            guard await recognizer.requestAuthorization() else {
                guidance.speak("Microphone or speech recognition permission is off. Please enable it in Settings.", interrupt: true)
                return
            }
            guidance.stopSpeaking()           // never listen to ourselves
            guidance.play(.nodeReached)       // tactile "I'm listening"
            if positioningSource == .glasses, glasses.isConnected {
                // The phone is in a pocket: listen through the glasses' microphone.
                recognizer.startListening(input: .external)
                do {
                    try await glasses.startMicrophone { [recognizer] buffer in recognizer.append(buffer) }
                } catch {
                    recognizer.stopListening(deliver: false)
                    guidance.speak("The glasses microphone did not open.", interrupt: true)
                }
            } else {
                recognizer.startListening()
            }
        }
    }

    private func closeGlassesMicrophone() {
        guard glasses.isMicOpen else { return }
        Task { await glasses.stopMicrophone() }
    }

    private func handle(transcript: String) {
        guidance.play(.turnLeft) // short double tap: "got it, thinking"
        let command = commandParser.parse(transcript)
        statusMessage = transcript.isEmpty ? nil : "Heard: “\(transcript)”"
        handle(command: command)
    }

    private func handle(appCommand: AppCommand) {
        switch appCommand {
        case .startListening:
            if !recognizer.isListening { toggleListening() }
        case .navigate(let poiID):
            handle(command: .navigate(poiID: poiID))
        }
    }

    private func handle(command: VoiceCommand) {
        if command != .unknown { unknownCommandCount = 0 }
        let position = NavigationGeometry.planarPosition(of: currentTransform)
        let heading = NavigationGeometry.heading(of: currentTransform)

        switch command {
        case .navigate(let poiID):
            guard let poi = engine.map.pois.first(where: { $0.id == poiID }) else {
                guidance.speak("I don't know that place.", interrupt: true)
                return
            }
            stopNavigation()
            selectedDestination = poi
            if localizationStatus.isReliable {
                startNavigation()
            } else {
                pendingDestinationID = poiID
                guidance.speak("Okay, \(poi.name). Waiting for tracking. Please look around slowly.", interrupt: true)
            }

        case .whereAmI:
            guard localizationStatus.isReliable else {
                guidance.speak("I'm still relocalizing. Please look around slowly.", interrupt: true)
                return
            }
            let description = LocationDescriber(map: engine.map).describe(position: position, heading: heading)
            guidance.speak(description?.spokenText ?? "This map has no named places yet.", interrupt: true)

        case .whatsNearby:
            guard localizationStatus.isReliable else {
                guidance.speak("I'm still relocalizing. Please look around slowly.", interrupt: true)
                return
            }
            let nearby = engine.nearby(position: position, heading: heading, maxDistance: 10, limit: 3)
            if nearby.isEmpty {
                guidance.speak("Nothing within ten meters.", interrupt: true)
            } else {
                let parts = nearby.map { "\($0.poi.name), \(Int($0.distance.rounded())) meters \($0.side.phrase)" }
                guidance.speak("Nearby: " + parts.joined(separator: ". ") + ".", interrupt: true)
            }

        case .repeatInstruction:
            if let instruction = currentInstruction {
                guidance.speak(instruction.spokenText, interrupt: true)
            } else if let message = statusMessage {
                guidance.speak(message, interrupt: true)
            } else {
                guidance.speak("No active route. Say a destination, or ask what's nearby.", interrupt: true)
            }

        case .stop:
            stopNavigation()
            pendingDestinationID = nil
            guidance.speak("Navigation stopped.", interrupt: true)

        case .unknown:
            unknownCommandCount += 1
            if unknownCommandCount >= 2 {
                let names = destinations.map(\.name).joined(separator: ", ")
                guidance.speak("I didn't catch that. You can say: take me to, where am I, what's nearby, repeat, or stop. Destinations are: \(names).", interrupt: true)
            } else {
                guidance.speak("I didn't catch that. Please try again.", interrupt: true)
            }
        }
    }

    // MARK: - Map / anchors

    /// Anchors are recorded for diagnostics only; the graph JSON (editable on
    /// the web) is the authority for node coordinates.
    private func applyAnchors(_ positions: [String: SIMD2<Float>]) {
        debug.anchoredNodes = positions.count
    }

    private func rebuildEngine() {
        let map = baseMap
        engine = PathfindingEngine(map: map)
        commandParser = CommandParser(pois: map.pois)
        proximityAnnouncer = ProximityAnnouncer(pois: map.pois)
        if let selected = selectedDestination {
            selectedDestination = map.pois.first { $0.id == selected.id }
        }
    }

    private func didChange(mode: AppMode) {
        switch mode {
        case .authoring:
            stopNavigation()
            recognizer.stopListening(deliver: false)
            guidance.stopSpeaking()
        case .navigation:
            reloadMapAndRestart()
            Task { await checkForMapUpdate() }
        }
    }

    // MARK: - Per-frame update

    private func handle(_ snapshot: PoseSnapshot) {
        updateDebug(with: snapshot)
        guard !isAuthoring else { return }

        let position = NavigationGeometry.planarPosition(of: snapshot.cameraTransform)
        let heading = NavigationGeometry.heading(of: snapshot.cameraTransform)

        if snapshot.trackingReliable {
            startPendingNavigationIfNeeded()
            announceProximity(position: position, heading: heading)
        }

        guard isNavigating, var tracker else { return }

        // Only trust the pose for route progress when tracking is normal;
        // during relocalization the pose can jump arbitrarily.
        let event: RouteEvent = snapshot.trackingReliable ? tracker.update(position: position) : .none
        self.tracker = tracker

        let instruction = makeInstruction(from: snapshot.cameraTransform)
            ?? lastInstruction
            ?? NavigationInstruction(direction: .straight, distance: 0,
                                     nextNodeName: selectedDestination?.name ?? "destination", isFinal: true)
        lastInstruction = instruction
        currentInstruction = instruction
        remainingDistance = tracker.remainingDistance(from: position)
        isOffRoute = snapshot.trackingReliable && tracker.isOffRoute(position: position)
        routeLeg = min(tracker.targetIndex + 1, tracker.path.count)
        routeLegCount = tracker.path.count
        debug.subGoal = tracker.targetNode.map(engine.displayName(of:)) ?? "arrived"

        let cue = policy.evaluate(instruction: instruction,
                                  routeEvent: event,
                                  isOffRoute: isOffRoute,
                                  trackingReliable: snapshot.trackingReliable,
                                  now: snapshot.timestamp)
        guard let cue, !recognizer.isListening else { return }

        guidance.deliver(cue)

        switch cue {
        case .arrived(let id):
            finishNavigation(at: selectedDestination?.name ?? id)
        case .offRoute:
            replanRoute(from: position)
        default:
            break
        }
    }

    private func startPendingNavigationIfNeeded() {
        guard let id = pendingDestinationID else { return }
        pendingDestinationID = nil
        selectedDestination = engine.map.pois.first { $0.id == id }
        startNavigation()
    }

    /// Passive commentary for exhibits and hazards, whether or not a route is active.
    private func announceProximity(position: SIMD2<Float>, heading: Float) {
        guard !recognizer.isListening else { return }
        for announcement in proximityAnnouncer.update(position: position, heading: heading) {
            if announcement.poi.category == .hazard {
                guidance.play(.offRoute)
                guidance.speak(announcement.spokenText, interrupt: true)
            } else {
                guidance.speak(announcement.spokenText, interrupt: false)
            }
        }
    }

    /// Recomputes the route from the nearest node after the user strays.
    private func replanRoute(from position: SIMD2<Float>) {
        guard let destination = selectedDestination, let start = engine.nearestNode(to: position) else { return }
        let path = engine.findPath(from: engine.name(of: start), to: destination.id)
        guard !path.isEmpty else { return }
        tracker = RouteTracker(path: path, thresholds: thresholds)
        routeLeg = 1
        routeLegCount = path.count
        debug.routeNodes = path.map(engine.displayName(of:))
    }

    private func finishNavigation(at name: String) {
        isNavigating = false
        hasArrived = true
        arrivedPlaceName = name
        tracker = nil
        remainingDistance = 0
        currentInstruction = nil
        routeLeg = 0
        routeLegCount = 0
        statusMessage = "Arrived at \(name)."
        debug.subGoal = "arrived"
    }

    /// Distance + turn toward the tracker's current target, or `nil` when there is no target.
    private func makeInstruction(from cameraTransform: simd_float4x4) -> NavigationInstruction? {
        guard let tracker, let target = tracker.targetNode else { return nil }
        let vector = engine.guidanceVector(from: cameraTransform, to: target)
        return NavigationInstruction(direction: TurnDirection(relativeAngle: vector.relativeAngle),
                                     distance: vector.distance,
                                     nextNodeName: tracker.spokenTargetName ?? engine.displayName(of: target),
                                     isFinal: tracker.isFinalLeg)
    }

    private func updateDebug(with snapshot: PoseSnapshot) {
        guard showDebug else { return }
        if positioningSource == .glasses {
            debug.fps = Double(glasses.framesPerSecond)
            debug.trackingState = "glasses \(glassesPositioning.fixes)/\(glassesPositioning.attempts) fixes"
            debug.featurePoints = 0
            debug.worldMapping = "immersal"
        } else {
            debug.fps = arManager.framesPerSecond
            debug.trackingState = arManager.trackingStateDescription
            debug.featurePoints = snapshot.featurePointCount
            debug.worldMapping = arManager.worldMappingStatus.label
        }
        debug.position = NavigationGeometry.planarPosition(of: snapshot.cameraTransform)
        debug.headingDegrees = NavigationGeometry.heading(of: snapshot.cameraTransform) * 180 / .pi
    }
}

extension ARFrame.WorldMappingStatus {
    var label: String {
        switch self {
        case .notAvailable: return "notAvailable"
        case .limited:      return "limited"
        case .extending:    return "extending"
        case .mapped:       return "mapped"
        @unknown default:   return "unknown"
        }
    }

    /// Good enough to persist a world map that will relocalize reliably.
    var isSaveable: Bool { self == .mapped || self == .extending }
}
