import AVFoundation
import Foundation
import NetworkExtension
import Observation
import OSLog
import UIKit

/// The app's one handle on the AiSee glasses.
///
/// Wraps the kit's connection service and device coordinator, keeps the
/// coordinator attached to whatever connection is live (the kit's one hard
/// rule for hosts), mirrors stream and mic state for the UI, and turns the
/// temple button into app actions. Everything the kit can do that this app
/// does not need — still photos — is left unexposed.
///
/// Vendor types never leave this file. The kit's `#else` stubs make it compile
/// for the simulator, where the glasses are simply never connected.
@MainActor
@Observable
final class GlassesService {

    /// What the one button does. The glasses detect the gesture in firmware
    /// and report key 1 / 2 / 3; the mapping is fixed because a blind visitor
    /// cannot browse a settings page to change it.
    enum KeyAction: Equatable {
        case talk
        case whereAmI
        case stopGuidance

        static func forKey(_ index: Int) -> KeyAction? {
            switch index {
            case 1: return .talk
            case 2: return .whereAmI
            case 3: return .stopGuidance
            default: return nil
            }
        }

        var label: String {
            switch self {
            case .talk:         return "Tap: talk"
            case .whereAmI:     return "Double tap: where am I"
            case .stopGuidance: return "Triple tap: stop guidance"
            }
        }
    }

    let connection: AiSeeConnectionService
    @ObservationIgnored let coordinator: AiSeeDeviceCoordinator

    private(set) var isStreaming = false
    private(set) var isMicOpen = false
    /// While true, a stream the SDK ends on its own (hotspot hiccup, glasses
    /// dozing) is restarted after a short pause. Set by whoever needs frames
    /// continuously; a user toggling the stream off clears it.
    var keepStreaming = false
    /// The most recent decoded frame, rendered for the on-screen preview while
    /// the app is in the foreground (every frame, or four a second). Never used for localization — see `onFrame`.
    private(set) var previewImage: UIImage?
    private(set) var framesPerSecond = 0
    /// How much later than its best this second's frames arrived, in ms: the
    /// delay queued up between the glasses' encoder and the phone. Nil when the
    /// stream carries no timestamps.
    private(set) var lagBuildUpMs: Int?
    /// What the glasses encode. Takes effect on the next stream start; the
    /// Glasses screen restarts a running stream after changing it.
    var streamSettings = AiSeeStreamSettings.load() {
        didSet { streamSettings.save() }
    }
    /// Render every frame for the preview (the default) instead of four a
    /// second. Four a second made the preview look up to 250 ms late. Either way
    /// nothing is rendered while the app is in the background.
    var smoothPreview = UserDefaults.standard.object(forKey: "glasses.stream.smoothPreview") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(smoothPreview, forKey: "glasses.stream.smoothPreview")
            fanout.previewInterval = smoothPreview ? 0 : 0.25
        }
    }
    private(set) var lastStreamError: String?
    /// Last few kit diagnostics, newest last.
    private(set) var log: [String] = []

    /// Every decoded frame, on the SDK's thread. Consumers copy what they need
    /// and return quickly.
    var onFrame: (@Sendable (AiSeeFrame) -> Void)? {
        get { fanout.onFrame }
        set { fanout.onFrame = newValue }
    }
    /// Temple-button gestures, on the main actor.
    @ObservationIgnored var onKeyPress: ((KeyAction) -> Void)?

    var isConnected: Bool { connection.state.isConnected }
    var deviceName: String? {
        if case .connected(let name) = connection.state { return name }
        return nil
    }

    /// The SDK-thread side of frame delivery. Lives outside the main actor so
    /// `receive` can run where the decoder calls it.
    @ObservationIgnored private let fanout = FrameFanout()

    private final class FrameFanout: @unchecked Sendable {
        private let lock = NSLock()
        private var _onFrame: (@Sendable (AiSeeFrame) -> Void)?
        private var lastPreviewAt: TimeInterval = 0
        private var frameCount = 0
        private var fpsWindowStart: TimeInterval = 0
        /// 0 renders every frame; otherwise the minimum gap between previews.
        private var _previewInterval: TimeInterval = 0
        /// False while the app is not in the foreground: nobody can see the
        /// preview, so no frame is rendered for it.
        private var _previewVisible = true
        // Lag build-up: arrival time minus the stream's timestamp, per frame. Its
        // absolute value is meaningless (two clocks), so we report how far this
        // second's average sits above the best frame of the last ten seconds.
        private var lagSum: Double = 0
        private var lagCount = 0
        private var lagSecondMin = Double.infinity
        private var lagRecentMins: [Double] = []

        private var _latest: AiSeeFrame?

        var onFrame: (@Sendable (AiSeeFrame) -> Void)? {
            get { lock.withLock { _onFrame } }
            set { lock.withLock { _onFrame = newValue } }
        }

        var latest: AiSeeFrame? {
            get { lock.withLock { _latest } }
            set { lock.withLock { _latest = newValue } }
        }

        var previewInterval: TimeInterval {
            get { lock.withLock { _previewInterval } }
            set { lock.withLock { _previewInterval = newValue } }
        }

        var previewVisible: Bool {
            get { lock.withLock { _previewVisible } }
            set { lock.withLock { _previewVisible = newValue } }
        }

        func resetLag() {
            lock.withLock {
                lagSum = 0; lagCount = 0; lagSecondMin = .infinity; lagRecentMins = []
            }
        }

        /// Whether to render a preview now, and once per second the fps figure
        /// and the lag build-up in milliseconds (nil without stream timestamps).
        func account(now: TimeInterval, presentationTime: CMTime) -> (renderPreview: Bool, fps: Int?, lagMs: Int??) {
            lock.withLock {
                frameCount += 1
                if presentationTime.isNumeric {
                    let lag = now - presentationTime.seconds
                    lagSum += lag
                    lagCount += 1
                    lagSecondMin = min(lagSecondMin, lag)
                }
                var fps: Int?
                var lagMs: Int??
                if now - fpsWindowStart >= 1 {
                    fps = frameCount
                    frameCount = 0
                    fpsWindowStart = now
                    if lagCount > 0 {
                        lagRecentMins.append(lagSecondMin)
                        if lagRecentMins.count > 10 { lagRecentMins.removeFirst() }
                        let floor = lagRecentMins.min() ?? lagSecondMin
                        lagMs = .some(Int(((lagSum / Double(lagCount)) - floor) * 1000))
                    } else {
                        lagMs = .some(nil)
                    }
                    lagSum = 0; lagCount = 0; lagSecondMin = .infinity
                }
                let render = _previewVisible && now - lastPreviewAt >= _previewInterval
                if render { lastPreviewAt = now }
                return (render, fps, lagMs)
            }
        }
    }

    init() {
        let sink: AiSeeLog = { line in
            Task { @MainActor in GlassesService.shared?.append(line) }
        }
        connection = AiSeeConnectionService(log: sink)
        coordinator = AiSeeDeviceCoordinator(log: sink)
        Self.shared = self
        fanout.previewInterval = smoothPreview ? 0 : 0.25
        fanout.previewVisible = UIApplication.shared.applicationState != .background
        let center = NotificationCenter.default
        let fanout = self.fanout
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            fanout.previewVisible = false
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            fanout.previewVisible = true
        }

        Task {
            await coordinator.setKeyPressObserver { [weak self] index in
                Task { @MainActor in
                    guard let self, let action = KeyAction.forKey(index) else { return }
                    self.onKeyPress?(action)
                }
            }
            await coordinator.setStateObserver { [weak self] micOpen, streaming in
                Task { @MainActor in
                    guard let self else { return }
                    self.isMicOpen = micOpen
                    if self.isStreaming != streaming {
                        self.isStreaming = streaming
                        if !streaming { self.previewImage = nil; self.framesPerSecond = 0 }
                    }
                }
            }
        }
        observeConnection()
    }

    /// The log sink is created before `self` exists, so it reaches the service
    /// through this. There is one glasses service per app.
    private static weak var shared: GlassesService?

    // MARK: - Connection

    func startScan() { connection.startScan() }
    func stopScan() { connection.stopScan() }
    func connect(_ id: UUID) { connection.connect(id) }
    func disconnect() { connection.disconnect() }
    func reconnectLastDevice() { connection.reconnectLastDevice() }
    func refreshBattery() async { await connection.refreshBattery() }

    /// Connects without anyone tapping anything: the last device if it is in
    /// range, otherwise glasses already paired with the phone in iOS Settings
    /// (the kit lists those with no signal reading, because they do not
    /// advertise). A blind visitor puts the glasses on and the app follows.
    func connectAutomatically() {
        guard !isConnected else { return }
        if UserDefaults.standard.string(forKey: AiSeeConnectionService.lastPeripheralKey) != nil {
            reconnectLastDevice()
        } else {
            startScan()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isConnected else { return }
            if case .connecting = self.connection.state { return }
            if let paired = self.connection.discovered.first(where: { $0.rssi == 0 }) {
                self.append("connection: auto-connecting to paired \(paired.name)")
                self.connect(paired.id)
            }
        }
    }

    private func observeConnection() {
        withObservationTracking {
            _ = connection.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.attachCoordinator()
                self.observeConnection()
            }
        }
    }

    /// The kit binds nothing itself: every connection change must be handed to
    /// the coordinator, or a capture ends up talking to a dead device.
    private func attachCoordinator() {
        #if canImport(RTKAIDeviceConnection) && !targetEnvironment(simulator)
        let live = connection.connection
        Task { await coordinator.attach(live) }
        #else
        Task { await coordinator.detach() }
        #endif
        if !isConnected {
            isStreaming = false
            isMicOpen = false
            previewImage = nil
        }
    }

    // MARK: - Live stream

    /// Tries a few times. Each attempt first forgets the Wi-Fi configurations
    /// this app registered: iOS only asks to join a network, and only really
    /// switches to it, when the configuration is new. With a stale one on file
    /// the join "succeeds" silently while the phone stays on the hotel Wi-Fi,
    /// and the stream then fails against the wrong network
    /// (`HotspotConnection.Failure.serverError`).
    func startStreaming() async throws {
        guard !isStreaming else { return }
        lastStreamError = nil
        var lastError: Error?
        for attempt in 1...3 {
            await forgetHotspotConfigurations()
            do {
                try await startStreamingOnce()
                return
            } catch {
                lastError = error
                append("livestream: attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw lastError ?? AiSeeError.streamUnavailable
    }

    /// Drops every Wi-Fi configuration this app has registered, so the next
    /// join is a fresh one. Only our own configurations are visible or removable.
    private func forgetHotspotConfigurations() async {
        let ssids = await withCheckedContinuation { continuation in
            NEHotspotConfigurationManager.shared.getConfiguredSSIDs { continuation.resume(returning: $0) }
        }
        guard !ssids.isEmpty else { return }
        for ssid in ssids { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }
        append("livestream: forgot Wi-Fi configuration for \(ssids.joined(separator: ", "))")
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func startStreamingOnce() async throws {
        fanout.resetLag()
        lagBuildUpMs = nil
        try await coordinator.startLiveStream(
            settings: streamSettings,
            onFrame: { [weak self] frame in self?.receive(frame) },
            onError: { [weak self] text in
                Task { @MainActor in self?.lastStreamError = text }
            },
            onTerminate: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    self.isStreaming = false
                    self.previewImage = nil
                    self.framesPerSecond = 0
                    self.lagBuildUpMs = nil
                    if let text { self.lastStreamError = text }
                    self.restartStreamIfWanted()
                }
            })
        isStreaming = await coordinator.streaming
        guard isStreaming else { throw AiSeeError.streamUnavailable }
    }

    private func restartStreamIfWanted() {
        guard keepStreaming else { return }
        Task { [weak self] in
            for attempt in 1...5 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.keepStreaming, self.isConnected, !self.isStreaming else { return }
                self.append("livestream: restarting (attempt \(attempt))")
                do {
                    try await self.startStreaming()
                    return
                } catch {
                    self.append("livestream: restart failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopStreaming() async {
        keepStreaming = false
        await coordinator.stopLiveStream()
        fanout.latest = nil
        isStreaming = false
        previewImage = nil
        framesPerSecond = 0
        lagBuildUpMs = nil
    }

    /// Stops and restarts a running stream so new `streamSettings` reach the
    /// glasses. Keeps `keepStreaming` as it was.
    func restartStreamForNewSettings() async throws {
        guard isStreaming else { return }
        let keep = keepStreaming
        await stopStreaming()
        keepStreaming = keep
        try await startStreaming()
    }

    /// SDK thread. Hands the frame to the localizer and, a few times a second,
    /// renders it for the preview.
    /// The most recent decoded frame, for one-off uses such as calibration.
    nonisolated func latestFrame() -> AiSeeFrame? { fanout.latest }

    private nonisolated func receive(_ frame: AiSeeFrame) {
        fanout.latest = frame
        fanout.onFrame?(frame)

        let (renderPreview, fps, lagMs) = fanout.account(now: ProcessInfo.processInfo.systemUptime,
                                                         presentationTime: frame.presentationTime)
        guard renderPreview || fps != nil else { return }
        let image = renderPreview ? frame.image : nil
        Task { @MainActor in
            if let image { self.previewImage = image }
            if let fps { self.framesPerSecond = fps }
            if let lagMs { self.lagBuildUpMs = lagMs }
        }
    }

    // MARK: - Microphone

    func startMicrophone(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        try await coordinator.startMicrophone(onBuffer: onBuffer)
        isMicOpen = await coordinator.micOpen
    }

    func stopMicrophone() async {
        await coordinator.stopMicrophone()
        isMicOpen = false
    }

    // MARK: - Diagnostics

    /// Mirrored to the unified log so `idevicesyslog -p AISEEBIN` (or Console)
    /// shows the kit's diagnostics without opening the sheet.
    private static let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "glasses")

    private func append(_ line: String) {
        DiagnosticsLog.write("glasses: \(line)")
        Self.logger.notice("\(line, privacy: .public)")
        log.append(line)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }
}

extension AiSeeStreamSettings {
    private static let key = "glasses.stream.settings"

    static func load(from defaults: UserDefaults = .standard) -> AiSeeStreamSettings {
        var s = AiSeeStreamSettings()
        guard let d = defaults.dictionary(forKey: key) else { return s }
        if let raw = d["size"] as? String, let size = Size(rawValue: raw) { s.size = size }
        if let fps = d["fps"] as? Int, fps > 0 { s.fps = UInt(fps) }
        if let kbps = d["kbps"] as? Int, kbps > 0 { s.kbps = UInt(kbps) }
        if let cbr = d["cbr"] as? Bool { s.constantBitrate = cbr }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(["size": size.rawValue, "fps": Int(fps), "kbps": Int(kbps), "cbr": constantBitrate],
                     forKey: Self.key)
    }
}
