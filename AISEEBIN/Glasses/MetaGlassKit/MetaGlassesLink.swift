//
// MetaGlassesLink.swift — MetaGlassKit
//
// Ray-Ban Meta glasses through Meta's Wearables Device Access Toolkit (DAT,
// `MWDATCore` + `MWDATCamera`). This is the only file that imports the SDK;
// the rest of the app sees the vendor-free surface below and the same
// `AiSeeFrame` values the AiSee glasses deliver.
//
// How the toolkit works, in the order it has to happen:
//   1. `Wearables.configure()` once at launch.
//   2. Registration: the Meta AI app approves this app and calls back through
//      the `aiseebin://` URL scheme (`handle(url:)`).
//   3. Camera permission, also granted in the Meta AI app.
//   4. A device session, then a camera on it, then the stream.
// Steps 2 and 3 switch apps, so they only ever run from a button.
//
// The stream comes over Bluetooth Classic as decoded portrait frames
// (720x1280 at "high"). The glasses may pause or stop the session on their
// own (taken off, folded, "Hey Meta", heat); a stopped session is rebuilt
// while streaming is still wanted.
//

import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Observation
import UIKit

/// Stream sizes the Ray-Ban Meta camera offers (portrait).
enum MetaStreamResolution: String, CaseIterable, Identifiable, Sendable {
    case high, medium, low

    var id: String { rawValue }
    var label: String {
        switch self {
        case .high: return "High (720×1280)"
        case .medium: return "Medium (504×896)"
        case .low: return "Low (360×640)"
        }
    }

    static let key = "glasses.rayban.resolution"
    static func load(from defaults: UserDefaults = .standard) -> MetaStreamResolution {
        defaults.string(forKey: key).flatMap(MetaStreamResolution.init(rawValue:)) ?? .high
    }
}

/// Frame rates the toolkit accepts. Positioning uses at most two frames a
/// second, and a low rate leaves more of the Bluetooth link for each frame.
enum MetaStreamFrameRate {
    static let choices: [UInt] = [2, 7, 15, 24, 30]
    static let key = "glasses.rayban.fps"
    static let defaultValue: UInt = 7

    static func load(from defaults: UserDefaults = .standard) -> UInt {
        let stored = UInt(max(defaults.integer(forKey: key), 0))
        return choices.contains(stored) ? stored : defaultValue
    }
}

enum MetaGlassesError: LocalizedError {
    case unavailable
    case notReady(RayBanStatus)
    case sessionDidNotStart
    case cameraUnavailable
    case captureFailed
    /// The glasses' microphone is not ours to open: iOS routes it as a headset.
    case microphoneIsSystemRouted

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Ray-Ban Meta support is not part of this build."
        case .notReady(let status):
            switch status {
            case .metaAppMissing: return "Install the Meta AI app first."
            case .needsRegistration, .registering: return "Connect to Meta AI first."
            case .needsCameraPermission: return "Allow the camera in Meta AI first."
            default: return "The Ray-Ban Meta glasses are not in reach."
            }
        case .sessionDidNotStart: return "The glasses did not start a session. Put them on and try again."
        case .cameraUnavailable: return "The glasses' camera did not open."
        case .captureFailed: return "The glasses did not take the photo."
        case .microphoneIsSystemRouted: return "Ray-Ban Meta microphones are used through the phone's audio input."
        }
    }
}

/// Hands frames from the SDK's thread to whoever is listening, and remembers
/// when the last one arrived.
private final class MetaFrameSink: @unchecked Sendable {
    // @unchecked: every stored property is read and written under `lock`.
    private let lock = NSLock()
    private var _onFrame: (@Sendable (AiSeeFrame) -> Void)?
    private var _lastFrameAt: TimeInterval = 0

    var onFrame: (@Sendable (AiSeeFrame) -> Void)? {
        get { lock.withLock { _onFrame } }
        set { lock.withLock { _onFrame = newValue } }
    }

    var lastFrameAt: TimeInterval { lock.withLock { _lastFrameAt } }

    func deliver(_ frame: AiSeeFrame, now: TimeInterval) {
        let handler: (@Sendable (AiSeeFrame) -> Void)? = lock.withLock {
            _lastFrameAt = now
            return _onFrame
        }
        handler?(frame)
    }
}

/// Turns whatever pixel format the SDK delivers into the 32BGRA buffers the
/// positioning code reads (`ImmersalFrameEncoder.copyBGRA`).
private final class BGRAConverter: @unchecked Sendable {
    // @unchecked: `pool` and its size are guarded by `lock`; CIContext is thread-safe.
    private let lock = NSLock()
    private let context = CIContext()
    private var pool: CVPixelBufferPool?
    private var poolSize: (Int, Int) = (0, 0)

    func bgra(from source: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA { return source }
        return render(CIImage(cvPixelBuffer: source))
    }

    func bgra(from image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        return render(CIImage(cgImage: cg))
    }

    private func render(_ image: CIImage) -> CVPixelBuffer? {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        guard width > 0, height > 0 else { return nil }
        let output: CVPixelBuffer? = lock.withLock {
            if pool == nil || poolSize != (width, height) {
                let attributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey: width,
                    kCVPixelBufferHeightKey: height,
                    kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                ]
                var made: CVPixelBufferPool?
                CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &made)
                pool = made
                poolSize = (width, height)
            }
            guard let pool else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            return buffer
        }
        guard let output else { return nil }
        context.render(image, to: output)
        return output
    }
}

#if canImport(MWDATCore) && canImport(MWDATCamera) && !NUS_APP
import MWDATCamera
import MWDATCore

@MainActor
@Observable
final class MetaGlassesLink {
    /// Whether this build carries Meta's toolkit at all.
    static let isSupported = true

    private(set) var status: RayBanStatus = .needsRegistration
    private(set) var battery: Int?
    /// True once frames are wanted; the stream itself may still be starting or paused.
    private(set) var isStreaming = false
    private(set) var lastError: String?
    /// True while a button press has us waiting on the Meta AI app.
    private(set) var isBusy = false

    var resolution = MetaStreamResolution.load() {
        didSet { UserDefaults.standard.set(resolution.rawValue, forKey: MetaStreamResolution.key) }
    }
    var frameRate = MetaStreamFrameRate.load() {
        didSet { UserDefaults.standard.set(Int(frameRate), forKey: MetaStreamFrameRate.key) }
    }

    @ObservationIgnored var onFrame: (@Sendable (AiSeeFrame) -> Void)? {
        get { sink.onFrame }
        set { sink.onFrame = newValue }
    }
    @ObservationIgnored var log: AiSeeLog?

    /// Seconds since the last frame arrived; `.infinity` before the first.
    var secondsSinceLastFrame: TimeInterval {
        let last = sink.lastFrameAt
        return last > 0 ? ProcessInfo.processInfo.systemUptime - last : .infinity
    }

    @ObservationIgnored private var inputs = RayBanInputs()
    @ObservationIgnored private let sink = MetaFrameSink()
    @ObservationIgnored private let converter = BGRAConverter()
    @ObservationIgnored private var watchers: [Task<Void, Never>] = []
    @ObservationIgnored private var deviceTokens = ListenerTokenBag()
    @ObservationIgnored private var watchedDevice: DeviceIdentifier?
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var camera: Camera?
    @ObservationIgnored private var sessionTokens = ListenerTokenBag()
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var photoWaiter: CheckedContinuation<Data, Error>?

    private static var configured = false

    /// Once, at app launch, before anything else touches the SDK.
    static func configure() {
        guard !configured else { return }
        do {
            try Wearables.configure()
            configured = true
        } catch {
            NSLog("MetaGlassesLink: configure failed: %@", String(describing: error))
        }
    }

    /// Hands a URL the Meta AI app opened us with to the SDK. Returns false
    /// for any other URL, so unrelated deep links are left alone.
    @discardableResult
    static func handle(url: URL) -> Bool {
        guard configured,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else { return false }
        Task {
            do { _ = try await Wearables.shared.handleUrl(url) } catch {
                NSLog("MetaGlassesLink: handleUrl failed: %@", String(describing: error))
            }
        }
        return true
    }

    init() {
        guard Self.configured else {
            lastError = "Meta's glasses toolkit did not start."
            return
        }
        let wearables = Wearables.shared
        apply { $0.registration = Self.map(wearables.registrationState) }
        watchers.append(Task { [weak self] in
            for await state in wearables.registrationStateStream() {
                guard let self else { return }
                self.apply { $0.registration = Self.map(state) }
                if state == .registered { await self.refreshCameraPermission() }
            }
        })
        watchers.append(Task { [weak self] in
            for await ids in wearables.devicesStream() {
                guard let self else { return }
                self.devicesChanged(ids)
            }
        })
    }

    // MARK: - Steps that open the Meta AI app (buttons only)

    func register() async {
        guard Self.configured, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            try await Wearables.shared.startRegistration()
        } catch {
            switch error {
            case .metaAINotInstalled: apply { $0.metaAppMissing = true }
            case .alreadyRegistered: apply { $0.registration = .registered }
            default: lastError = error.description
            }
            log?("meta: registration failed: \(error.description)")
        }
    }

    func requestCamera() async {
        guard Self.configured, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            let granted = try await Wearables.shared.requestPermission(.camera) == .granted
            apply { $0.cameraGranted = granted }
            if !granted { lastError = "The camera was not allowed in Meta AI." }
        } catch {
            if error == .metaAINotInstalled { apply { $0.metaAppMissing = true } }
            lastError = error.description
            log?("meta: camera permission failed: \(error.description)")
        }
    }

    /// A silent check; never opens Meta AI.
    func refreshCameraPermission() async {
        guard Self.configured, inputs.registration == .registered else { return }
        if let status = try? await Wearables.shared.checkPermissionStatus(.camera) {
            apply { $0.cameraGranted = status == .granted }
        }
    }

    // MARK: - Devices

    private func devicesChanged(_ ids: [DeviceIdentifier]) {
        let wearables = Wearables.shared
        let devices = ids.compactMap { wearables.deviceForIdentifier($0) }
        let chosen = devices.first { $0.linkState == .connected } ?? devices.first
        if chosen?.identifier != watchedDevice {
            deviceTokens.clear()
            watchedDevice = chosen?.identifier
            chosen?.addDeviceStateListener { [weak self] state in
                Task { @MainActor [weak self] in self?.deviceStateChanged(state) }
            }.store(in: deviceTokens)
        }
        apply {
            $0.deviceName = chosen?.nameOrId()
            $0.linked = chosen?.linkState == .connected
        }
        battery = chosen?.batteryLevel
        if chosen != nil { Task { await refreshCameraPermission() } }
    }

    private func deviceStateChanged(_ state: DeviceState) {
        battery = state.batteryLevel
        apply { $0.linked = state.linkState == .connected }
        if state.linkState == .connected {
            Task { await refreshCameraPermission() }
            if isStreaming, session == nil { scheduleRebuild() }
        }
    }

    // MARK: - Streaming

    func startStreaming() async throws {
        guard Self.configured else { throw MetaGlassesError.unavailable }
        guard status.isConnected else { throw MetaGlassesError.notReady(status) }
        isStreaming = true
        lastError = nil
        do {
            try await openSession()
        } catch {
            isStreaming = false
            await closeSession()
            lastError = error.localizedDescription
            throw error
        }
    }

    func stopStreaming() async {
        isStreaming = false
        rebuildTask?.cancel()
        rebuildTask = nil
        await closeSession()
    }

    /// Applies new resolution / frame-rate settings to a running stream.
    func restartStreamForNewSettings() async throws {
        guard isStreaming else { return }
        await closeSession()
        try await openSession()
    }

    private func openSession() async throws {
        await closeSession()
        let wearables = Wearables.shared
        let session = try wearables.createSession(deviceSelector: AutoDeviceSelector(wearables: wearables))
        self.session = session

        session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in self?.sessionStateChanged(state, of: session) }
        }.store(in: sessionTokens)
        session.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                self?.lastError = error.description
                self?.log?("meta: session error: \(error.description)")
            }
        }.store(in: sessionTokens)

        // Subscribe before start() so the first transition is not missed.
        let states = session.stateStream()
        try session.start()
        let started = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in states {
                    if state == .started { return true }
                    if state == .stopped { return false }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard started else { throw MetaGlassesError.sessionDidNotStart }

        let config = StreamConfiguration(videoCodec: .raw, resolution: Self.sdkResolution(resolution), frameRate: frameRate)
        guard let camera = try session.addCamera(config: config) else { throw MetaGlassesError.cameraUnavailable }
        self.camera = camera
        let stream = camera.stream
        let sink = self.sink
        let converter = self.converter

        stream.videoFramePublisher.listen { frame in
            // SDK thread: convert and hand on without touching the main actor.
            let sample = frame.sampleBuffer
            let buffer: CVPixelBuffer?
            if let image = CMSampleBufferGetImageBuffer(sample) {
                buffer = converter.bgra(from: image)
            } else {
                // No pixel buffer in the sample: render the SDK's own image.
                buffer = frame.makeUIImage().flatMap { converter.bgra(from: $0) }
            }
            guard let buffer else { return }
            // Every raw frame is a whole picture, so each counts as a keyframe.
            sink.deliver(AiSeeFrame(pixelBuffer: buffer,
                                    presentationTime: CMSampleBufferGetPresentationTimeStamp(sample),
                                    compressedBytes: 0, isKeyframe: true),
                         now: ProcessInfo.processInfo.systemUptime)
        }.store(in: sessionTokens)
        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in self?.log?("meta: stream \(String(describing: state))") }
        }.store(in: sessionTokens)
        stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                self?.lastError = error.description
                self?.log?("meta: stream error: \(error.description)")
                if error == .permissionDenied { self?.apply { $0.cameraGranted = false } }
            }
        }.store(in: sessionTokens)
        stream.photoDataPublisher.listen { [weak self] photo in
            Task { @MainActor [weak self] in self?.photoArrived(photo) }
        }.store(in: sessionTokens)

        stream.start()
        log?("meta: stream requested \(resolution.rawValue) @ \(frameRate) fps")
    }

    private func closeSession() async {
        photoWaiter?.resume(throwing: MetaGlassesError.captureFailed)
        photoWaiter = nil
        let tokens = sessionTokens
        sessionTokens = ListenerTokenBag()
        await tokens.cancelAll()
        camera?.stop()
        camera = nil
        session?.stop()
        session = nil
        apply { $0.sessionPaused = false }
    }

    private func sessionStateChanged(_ state: DeviceSessionState, of changed: DeviceSession) {
        guard changed === session else { return }
        log?("meta: session \(state.description)")
        switch state {
        case .paused:
            apply { $0.sessionPaused = true }
        case .started:
            apply { $0.sessionPaused = false }
        case .stopped:
            // Terminal: the glasses ended it. Build a new one while frames are wanted.
            Task {
                await closeSession()
                if isStreaming { scheduleRebuild() }
            }
        default:
            break
        }
    }

    /// Retries every few seconds until a session opens, streaming is no
    /// longer wanted, or the glasses are gone (the link coming back restarts it).
    private func scheduleRebuild() {
        guard rebuildTask == nil else { return }
        rebuildTask = Task { [weak self] in
            defer { self?.rebuildTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, self.isStreaming, self.session == nil else { return }
                guard self.status.isConnected else { return }
                do {
                    try await self.openSession()
                    return
                } catch {
                    await self.closeSession()
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Still photo

    /// A JPEG taken by the glasses while the stream runs.
    func captureStill() async throws -> Data {
        guard let stream = camera?.stream, photoWaiter == nil else { throw MetaGlassesError.captureFailed }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.photoWaiter?.resume(throwing: MetaGlassesError.captureFailed)
            self?.photoWaiter = nil
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            photoWaiter = continuation
            if !stream.capturePhoto(format: .jpeg) {
                photoWaiter = nil
                continuation.resume(throwing: MetaGlassesError.captureFailed)
            }
        }
    }

    private func photoArrived(_ photo: PhotoData) {
        guard let waiter = photoWaiter else { return }
        photoWaiter = nil
        if photo.format == .jpeg {
            waiter.resume(returning: photo.data)
        } else if let jpeg = UIImage(data: photo.data)?.jpegData(compressionQuality: 0.9) {
            waiter.resume(returning: jpeg)
        } else {
            waiter.resume(throwing: MetaGlassesError.captureFailed)
        }
    }

    // MARK: - Helpers

    private func apply(_ change: (inout RayBanInputs) -> Void) {
        change(&inputs)
        let resolved = RayBanStatus.resolve(inputs)
        if resolved != status {
            status = resolved
            log?("meta: status \(String(describing: resolved))")
        }
    }

    private static func map(_ state: RegistrationState) -> RayBanInputs.Registration {
        switch state {
        case .unavailable: return .unavailable
        case .available: return .available
        case .registering: return .registering
        case .registered: return .registered
        @unknown default: return .unavailable
        }
    }

    private static func sdkResolution(_ resolution: MetaStreamResolution) -> StreamingResolution {
        switch resolution {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

#else

/// Builds without Meta's toolkit (the NUS app, and any build where the package
/// is missing): the same surface, permanently unavailable.
@MainActor
@Observable
final class MetaGlassesLink {
    static let isSupported = false

    private(set) var status: RayBanStatus = .metaAppMissing
    private(set) var battery: Int?
    private(set) var isStreaming = false
    private(set) var lastError: String? = MetaGlassesError.unavailable.errorDescription
    private(set) var isBusy = false
    var resolution = MetaStreamResolution.load()
    var frameRate = MetaStreamFrameRate.load()
    @ObservationIgnored var onFrame: (@Sendable (AiSeeFrame) -> Void)?
    @ObservationIgnored var log: AiSeeLog?
    var secondsSinceLastFrame: TimeInterval { .infinity }

    static func configure() {}
    @discardableResult static func handle(url: URL) -> Bool { false }

    func register() async {}
    func requestCamera() async {}
    func refreshCameraPermission() async {}
    func startStreaming() async throws { throw MetaGlassesError.unavailable }
    func stopStreaming() async {}
    func restartStreamForNewSettings() async throws {}
    func captureStill() async throws -> Data { throw MetaGlassesError.unavailable }
}

#endif
