import AVFoundation
import Foundation
import Observation
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
    /// The most recent decoded frame, rendered at most a few times a second
    /// for the on-screen preview. Never used for localization — see `onFrame`.
    private(set) var previewImage: UIImage?
    private(set) var framesPerSecond = 0
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

        private var _latest: AiSeeFrame?

        var onFrame: (@Sendable (AiSeeFrame) -> Void)? {
            get { lock.withLock { _onFrame } }
            set { lock.withLock { _onFrame = newValue } }
        }

        var latest: AiSeeFrame? {
            get { lock.withLock { _latest } }
            set { lock.withLock { _latest = newValue } }
        }

        /// Whether to render a preview now, and the fps figure once per second.
        func account(now: TimeInterval) -> (renderPreview: Bool, fps: Int?) {
            lock.withLock {
                frameCount += 1
                var fps: Int?
                if now - fpsWindowStart >= 1 {
                    fps = frameCount
                    frameCount = 0
                    fpsWindowStart = now
                }
                let render = now - lastPreviewAt >= 0.25
                if render { lastPreviewAt = now }
                return (render, fps)
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
        #if canImport(RTKAIDeviceConnection)
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

    func startStreaming() async throws {
        guard !isStreaming else { return }
        lastStreamError = nil
        try await coordinator.startLiveStream(
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
                    if let text { self.lastStreamError = text }
                }
            })
        isStreaming = await coordinator.streaming
        guard isStreaming else { throw AiSeeError.streamUnavailable }
    }

    func stopStreaming() async {
        await coordinator.stopLiveStream()
        fanout.latest = nil
        isStreaming = false
        previewImage = nil
        framesPerSecond = 0
    }

    /// SDK thread. Hands the frame to the localizer and, a few times a second,
    /// renders it for the preview.
    /// The most recent decoded frame, for one-off uses such as calibration.
    nonisolated func latestFrame() -> AiSeeFrame? { fanout.latest }

    private nonisolated func receive(_ frame: AiSeeFrame) {
        fanout.latest = frame
        fanout.onFrame?(frame)

        let (renderPreview, fps) = fanout.account(now: ProcessInfo.processInfo.systemUptime)
        guard renderPreview || fps != nil else { return }
        let image = renderPreview ? frame.image : nil
        Task { @MainActor in
            if let image { self.previewImage = image }
            if let fps { self.framesPerSecond = fps }
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

    private func append(_ line: String) {
        log.append(line)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }
}
