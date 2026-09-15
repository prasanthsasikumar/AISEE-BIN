//
// AiSeeDeviceCoordinator.swift — AiSeeGlassKit
//
// The only object that starts or stops anything on the glasses. It keeps the
// mic / livestream state, asks AiSeeSequencing for a plan before every still,
// and executes it. Consumers (the sample UI, Hermes) never touch the SDK's
// routines directly, which is how the FINDINGS rules stay enforced.
//

import AVFoundation
import Foundation

#if canImport(RTKAIDeviceConnection)
import RTKAIDeviceConnection

actor AiSeeDeviceCoordinator {
    private let log: AiSeeLog
    private var connection: IntelligenceDeviceConnection?

    private(set) var micOpen = false { didSet { if oldValue != micOpen { notifyStateChange() } } }
    private(set) var streaming = false { didSet { if oldValue != streaming { notifyStateChange() } } }
    /// Latched when a shot returns `DeviceFailure.failure(code: 4)`. The camera is
    /// gone until the glasses are power-cycled (FINDINGS §1), so every later
    /// `capturePhoto()` fails immediately until a new connection is attached.
    private(set) var unavailableUntilReconnect = false
    private var lastStreamStop: Date?
    private var captureInFlight = false
    private var latestFrameJPEG: (() -> Data?)?
    private var reopenMic: (() async -> Void)?
    private var closeMic: (() async -> Void)?
    private var liveStream: AiSeeLiveStream?
    private var streamStarting = false
    private var microphone: AiSeeMicrophone?
    private var micBufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var micStarting = false
    private var pendingStreamStop = false
    private var pendingMicStop = false
    private var onStateChange: (@Sendable (_ micOpen: Bool, _ streaming: Bool) -> Void)?

    init(log: @escaping AiSeeLog) { self.log = log }

    /// Notified whenever `micOpen` or `streaming` changes, including changes the
    /// host did not ask for (an SDK-initiated stream termination, a failed mic
    /// reopen). Hosts mirror their own UI state from this.
    /// Physical key presses on the glasses (`keyIdx` as the SDK reports it; the
    /// vendor demo maps 1 → photo, 2 → livestream). The kit only reports them —
    /// mapping a key to an action is the host's decision.
    private var keyPressObserver: (@Sendable (_ keyIndex: Int) -> Void)?
    func setKeyPressObserver(_ observer: (@Sendable (_ keyIndex: Int) -> Void)?) {
        keyPressObserver = observer
    }
    private func keyPressed(_ index: Int) {
        log("key: pressed \(index)")
        keyPressObserver?(index)
    }

    func setStateObserver(_ observer: (@Sendable (_ micOpen: Bool, _ streaming: Bool) -> Void)?) {
        onStateChange = observer
    }

    private func notifyStateChange() { onStateChange?(micOpen, streaming) }

    func attach(_ connection: IntelligenceDeviceConnection?) {
        // Every piece of state below describes the device we are leaving, so a swap
        // to a different connection resets exactly as a detach does — otherwise a
        // reconnect inherits the old device's mic/stream flags.
        if self.connection !== connection {
            resetDeviceState()
            self.connection?.mediaRoutine.onKeyPressNotification = nil
        }
        self.connection = connection
        connection?.mediaRoutine.onKeyPressNotification = { [weak self] index in
            Task { await self?.keyPressed(index) }
        }
        if connection != nil {
            // A power cycle is the only way out of the wedge, and it always brings a
            // new connection with it — so attaching one clears the latch.
            unavailableUntilReconnect = false
        }
    }

    /// Vendor-type-free detach, so hosts (and the `#else` stub) have one name to call.
    func detach() { attach(nil) }

    private func resetDeviceState() {
        micOpen = false
        streaming = false
        lastStreamStop = nil
        liveStream = nil
        latestFrameJPEG = nil
        microphone = nil
        micBufferHandler = nil
        closeMic = nil
        reopenMic = nil
        micSuspendedForCapture = false
        micReopenCancelled = true
    }

    // MARK: Still photo

    func capturePhoto() async throws -> Data {
        // Once wedged (FINDINGS §1) the camera refuses every shot until the
        // glasses are power-cycled — fail fast instead of shooting into a dead device.
        if unavailableUntilReconnect { throw AiSeeError.deviceWedged }
        // Serialize: a second caller waits, never fails.
        while captureInFlight { try await Task.sleep(for: .milliseconds(50)) }
        // The capture we queued behind may be the one that wedged the device.
        if unavailableUntilReconnect { throw AiSeeError.deviceWedged }
        // Bind the connection only once it is our turn: `attach()` may have
        // swapped or cleared it while we waited above.
        guard let connection else { throw AiSeeError.notConnected }
        captureInFlight = true
        defer { captureInFlight = false }

        let plan = AiSeeSequencing.stillPhotoPlan(
            state: .init(micOpen: micOpen, streaming: streaming, lastStreamStop: lastStreamStop), now: Date())
        log("capture plan: \(plan)")

        var result: Data?
        var midPlanMicClose = false
        do {
            for step in plan {
                switch step {
                case .serveLatestFrame:
                    guard let jpeg = latestFrameJPEG?() else { throw AiSeeError.streamUnavailable }
                    log("✅ photo served from live frame (\(jpeg.count) bytes)")
                    result = jpeg
                case .wait(let ms):
                    try await Task.sleep(for: .milliseconds(ms))
                case .closeMic:
                    await closeMic?()
                case .reopenMic:
                    await reopenMic?()
                case .shoot:
                    // Every `.wait` and every SDK await above suspended the actor, so
                    // the state this plan was built from may no longer hold. Re-read it
                    // here — this is the last line of defence against the F1 wedge.
                    guard self.connection === connection else { throw AiSeeError.notConnected }
                    if streaming {
                        guard let jpeg = latestFrameJPEG?() else { throw AiSeeError.streamUnavailable }
                        log("⚠️ live stream opened mid-plan — serving latest frame instead of shooting")
                        result = jpeg
                        continue
                    }
                    if micOpen && !micSuspendedForCapture {
                        log("⚠️ mic opened mid-plan — closing it before the shot")
                        await closeMic?()
                        midPlanMicClose = true
                        try await Task.sleep(for: .milliseconds(AiSeeSequencing.micCloseLeadMs))
                        try await Task.sleep(for: .milliseconds(AiSeeSequencing.micSettleMs))
                    }
                    result = try await AiSeePhotoCapture(connection: connection, log: log).capture()
                    if midPlanMicClose && !plan.contains(.reopenMic) { await reopenMic?() }
                }
            }
        } catch {
            // Any failure — including cancellation inside a `.wait` — must still hand
            // the mic back if the plan (or the mid-plan close above) took it away.
            if plan.contains(.reopenMic) || midPlanMicClose { await reopenMic?() }
            if let aiSee = error as? AiSeeError, case .deviceWedged = aiSee { unavailableUntilReconnect = true }
            throw error
        }
        guard let result else { throw AiSeeError.sdk(NSError(domain: "AiSee", code: -1, userInfo: [NSLocalizedDescriptionKey: "empty plan"])) }
        return result
    }

    // MARK: Live stream

    /// - Parameters:
    ///   - onError: errors the running stream reports that are not an end of stream.
    ///     A start failure is thrown, not routed here.
    ///   - onTerminate: the stream ended — error text, or nil for a clean end.
    ///     Fired for SDK-initiated ends only; an explicit `stopLiveStream()` does not fire it.
    func startLiveStream(onFrame: @escaping @Sendable (AiSeeFrame) -> Void,
                         onError: @escaping @Sendable (String) -> Void,
                         onTerminate: @escaping @Sendable (String?) -> Void) async throws {
        // One operation at a time: a stream opened mid-capture would race the shot.
        guard !captureInFlight else { throw AiSeeError.captureInProgress }
        guard let connection else { throw AiSeeError.notConnected }
        guard !streaming && !streamStarting else { return }
        streamStarting = true
        defer { streamStarting = false; pendingStreamStop = false }
        let stream = AiSeeLiveStream(connection: connection, log: log)
        try await stream.start(
            onFrame: onFrame,
            // Not fired today: start failures throw, terminations go to onTerminate.
            // Kept as the hook for a non-terminal error the running stream reports.
            onError: onError,
            onTerminate: { [weak self, weak stream] text in
                Task {
                    guard let self, let stream else { return }
                    await self.streamDidTerminate(stream, text: text, onTerminate: onTerminate)
                }
            })
        // `stream.start` suspended the actor. If a stop or a detach arrived while it
        // ran, tear the stream straight back down instead of installing it.
        guard !pendingStreamStop, self.connection === connection else {
            await stream.stop()
            lastStreamStop = Date()
            log("livestream: start abandoned (stopped/detached meanwhile)")
            return
        }
        liveStream = stream
        streaming = true
        latestFrameJPEG = { [weak stream] in
            stream?.latestFrame?.image?.jpegData(compressionQuality: 0.85)
        }
    }

    /// Called from `AiSeeLiveStream`'s `onTerminate` hook — an SDK-initiated
    /// end (clean or errored) must reset `streaming` even though nobody
    /// called `stopLiveStream()`. Guarded by identity so a stale callback
    /// from an already-replaced/stopped stream can't clobber current state.
    private func streamDidTerminate(_ stream: AiSeeLiveStream, text: String?,
                                     onTerminate: @escaping @Sendable (String?) -> Void) async {
        guard liveStream === stream else { return }
        liveStream = nil
        latestFrameJPEG = nil
        streaming = false
        // Tell the host before tearing down: nothing about the cleanup below changes
        // what it needs to know, and it should not wait on the decoder drain.
        onTerminate(text)
        // The SDK ended the stream, but nothing tore our side down: without this the
        // decoder session and the retained latest frame outlive it. Local cleanup
        // only — the SDK is already done with this stream.
        await stream.releaseAfterTermination()
        // Stamped after the cleanup, as in stopLiveStream(), so the 1 s post-stream
        // settle is measured from when the stream was actually released.
        lastStreamStop = Date()
    }

    func stopLiveStream() async {
        if streamStarting {
            // `startLiveStream` is inside its start await; it honours this after it returns.
            pendingStreamStop = true
            log("livestream: stop requested during start — will stop once started")
        }
        guard let stream = liveStream else { return }
        await stream.stop()
        // `stream.stop()` suspended the actor: only clear state if this is still the
        // installed stream (a terminate callback may have replaced/cleared it).
        guard liveStream === stream else { return }
        liveStream = nil
        latestFrameJPEG = nil
        streaming = false
        lastStreamStop = Date()
    }

    // MARK: Microphone

    func startMicrophone(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        // FINDINGS §1: the mic must never open across a snapshot().
        guard !captureInFlight else { throw AiSeeError.captureInProgress }
        guard let connection else { throw AiSeeError.notConnected }
        guard !micOpen && !micStarting else { return }
        micStarting = true
        defer { micStarting = false; pendingMicStop = false }
        let mic = AiSeeMicrophone(connection: connection, log: log)
        try await mic.start(onBuffer: onBuffer)
        // `mic.start` suspended the actor. If a stop or a detach arrived while it
        // ran, close the mic we just opened instead of installing it — the same
        // contract startLiveStream honours via pendingStreamStop.
        guard !pendingMicStop, self.connection === connection else {
            await mic.stop(releasingHandlers: microphone == nil)
            log("mic: start abandoned (stopped/detached meanwhile)")
            return
        }
        microphone = mic
        micBufferHandler = onBuffer
        micOpen = true
        // The still-photo plan uses these to close/reopen around a shot.
        closeMic = { [weak self] in await self?.closeMicForCapture() }
        reopenMic = { [weak self] in await self?.reopenMicAfterCapture() }
    }

    func stopMicrophone() async {
        if micStarting {
            // `startMicrophone` is inside its start await; it honours this after it returns.
            pendingMicStop = true
            log("mic: stop requested during start — will stop once started")
        }
        if micSuspendedForCapture || (micOpen && microphone == nil) {
            // No live mic object right now: either it is closed for a capture in
            // flight, or `reopenMicAfterCapture()` is still inside its `mic.start`
            // await. Cancel the pending reopen — it will stop the mic it started
            // rather than installing it.
            micSuspendedForCapture = false
            micReopenCancelled = true
            micBufferHandler = nil
            micOpen = false
            closeMic = nil
            reopenMic = nil
            log("mic: stop requested during capture — will not reopen")
            return
        }
        // Flip state synchronously, before the first await, so a
        // closeMicForCapture() interleaved during mic.stop() finds
        // `microphone == nil` and returns instead of racing this function to
        // stop the same mic object a second time.
        guard let mic = microphone else { return }
        microphone = nil
        micBufferHandler = nil
        micOpen = false
        closeMic = nil
        reopenMic = nil
        await mic.stop()
    }

    private var micSuspendedForCapture = false
    /// Set by `stopMicrophone()` / `attach(nil)` while a reopen is in flight, so the
    /// reopen can tell "still wanted" from "the user restarted the mic meanwhile".
    private var micReopenCancelled = false

    private func closeMicForCapture() async {
        // Flip state synchronously, before the first await, so a
        // stopMicrophone() interleaved during mic.stop() sees
        // micSuspendedForCapture already true and takes that branch instead
        // of racing this function to clear/rebuild `microphone`.
        guard let mic = microphone else { return }
        microphone = nil
        micSuspendedForCapture = true
        micReopenCancelled = false
        await mic.stop()
        log("mic: closed for capture")
    }

    private func reopenMicAfterCapture() async {
        guard micSuspendedForCapture, let conn = connection, let handler = micBufferHandler else { return }
        micSuspendedForCapture = false
        micReopenCancelled = false
        let mic = AiSeeMicrophone(connection: conn, log: log)
        do {
            try await mic.start(onBuffer: handler)
        } catch {
            microphone = nil
            micOpen = false
            log("mic: reopen failed: \(error)")
            return
        }
        // `mic.start` suspended the actor: `stopMicrophone()` or `attach(nil)` may
        // have run meanwhile. Don't install a mic nobody asked for — stop it instead.
        guard micOpen, !micReopenCancelled, connection === conn else {
            await mic.stop(releasingHandlers: microphone == nil)
            log("mic: reopen abandoned (stopped/detached meanwhile)")
            return
        }
        microphone = mic
        log("mic: reopened after capture")
    }
}

#else

/// Simulator / no-SDK stub. Mirrors the full public surface of the real actor so
/// hosts compile unchanged; every operation reports "not connected".
actor AiSeeDeviceCoordinator {
    init(log: @escaping AiSeeLog) {}
    var micOpen: Bool { false }
    var streaming: Bool { false }
    var unavailableUntilReconnect: Bool { false }
    func detach() {}
    func setKeyPressObserver(_ observer: (@Sendable (_ keyIndex: Int) -> Void)?) {}
    func setStateObserver(_ observer: (@Sendable (_ micOpen: Bool, _ streaming: Bool) -> Void)?) {}
    func capturePhoto() async throws -> Data { throw AiSeeError.notConnected }
    func startLiveStream(onFrame: @escaping @Sendable (AiSeeFrame) -> Void,
                         onError: @escaping @Sendable (String) -> Void,
                         onTerminate: @escaping @Sendable (String?) -> Void) async throws {
        throw AiSeeError.notConnected
    }
    func stopLiveStream() async {}
    func startMicrophone(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        throw AiSeeError.notConnected
    }
    func stopMicrophone() async {}
}

#endif
