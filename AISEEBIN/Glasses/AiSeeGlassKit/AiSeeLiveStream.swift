//
// AiSeeLiveStream.swift — AiSeeGlassKit
//
// LiveCaptureStream (Wi-Fi hotspot, H.264) → decoded AiSeeFrame callbacks.
// Keeps the latest frame so a still can be served from it while streaming.
// stop() awaits the SDK teardown, which FINDINGS measured at 1–7 s; the
// coordinator adds the 1 s settle on top.
//

import CoreMedia
import Foundation

#if canImport(RTKAIDeviceConnection)
import RTKAIDeviceConnection

/// `@unchecked Sendable` is safe because every piece of mutable state below is
/// only ever touched inside `lock`: the SDK delivers samples on its own thread
/// while `start`/`stop` run on the coordinator's actor. `decoder` is the one
/// exception — it is used from the sample-delivery thread only, and `stop()`
/// waits for an in-flight decode (the `decoding` flag) before invalidating it.
final class AiSeeLiveStream: NSObject, LiveStreamSampleReceiving, @unchecked Sendable {
    private let connection: IntelligenceDeviceConnection
    private let log: AiSeeLog
    private let decoder = AiSeeH264Decoder()
    private let lock = NSLock()
    // All of the below: `lock`-guarded.
    private var capture: LiveCaptureStream?
    private var _latest: AiSeeFrame?
    private var onFrame: (@Sendable (AiSeeFrame) -> Void)?
    private var onError: (@Sendable (String) -> Void)?
    private var onTerminate: (@Sendable (String?) -> Void)?
    private var frames = 0
    private var stopped = false
    private var decoding = false

    init(connection: IntelligenceDeviceConnection, log: @escaping AiSeeLog) {
        self.connection = connection
        self.log = log
    }

    var isStreaming: Bool { lock.withLock { capture }?.isStreaming ?? false }

    var latestFrame: AiSeeFrame? { lock.withLock { _latest } }

    func start(onFrame: @escaping @Sendable (AiSeeFrame) -> Void,
               onError: @escaping @Sendable (String) -> Void,
               onTerminate: @escaping @Sendable (String?) -> Void) async throws {
        guard connection.deviceIsConnected else { throw AiSeeError.notConnected }
        let stream = LiveCaptureStream(accessoryConnection: connection)
        lock.withLock {
            self.onFrame = onFrame
            self.onError = onError
            self.onTerminate = onTerminate
            self.frames = 0
            self.stopped = false
            self.capture = stream
        }
        let t0 = Date()
        do {
            let info = try await stream.start(via: .wifi, sampleReceivers: [self])
            log("livestream: started in \(Int(Date().timeIntervalSince(t0) * 1000))ms, video=\(info.video != nil) audio=\(info.audio != nil)")
        } catch {
            lock.withLock { self.capture = nil; self.stopped = true }
            log("livestream: start failed: \(error)")
            throw AiSeeError.sdk(error)
        }
    }

    /// Host-initiated teardown: stops the SDK stream, then releases our side.
    /// Idempotent — safe to call twice.
    func stop() async {
        if let stream = detachHandlers() {
            let t0 = Date()
            do { try await stream.stop() } catch { log("livestream: stop error: \(error)") }
            let frameCount = lock.withLock { frames }
            log("livestream: stopped after \(Int(Date().timeIntervalSince(t0) * 1000))ms, \(frameCount) frames")
        }
        await releaseDecoder()
    }

    /// Local cleanup for a stream the SDK has already ended (`didTerminateWith`).
    /// Same tail as `stop()`, but issues no second `LiveCaptureStream.stop()` —
    /// the SDK is done with it, and FINDINGS §2 says its teardown is already
    /// slow and non-deterministic without us asking twice.
    func releaseAfterTermination() async {
        _ = detachHandlers()
        let frameCount = lock.withLock { frames }
        log("livestream: released after termination, \(frameCount) frames")
        await releaseDecoder()
    }

    /// Closes the gate and hands back the SDK stream, if we still hold one.
    private func detachHandlers() -> LiveCaptureStream? {
        lock.withLock {
            let current = capture
            capture = nil
            stopped = true
            onFrame = nil
            onError = nil
            onTerminate = nil
            return current
        }
    }

    private func releaseDecoder() async {
        // `stopped` keeps new decodes out; wait out one already in the decoder so
        // the session is not invalidated underneath it.
        var spins = 0
        while lock.withLock({ decoding }), spins < 100 {
            spins += 1
            try? await Task.sleep(for: .milliseconds(2))
        }
        decoder.invalidate()
        lock.withLock { _latest = nil }
    }

    // MARK: LiveStreamSampleReceiving (SDK thread)

    func stream(_ stream: LiveCaptureStream, didStartWithMedia format: LiveCaptureStream.StreamFormat) {}

    func stream(_ stream: LiveCaptureStream, didGenerate sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.formatDescription?.mediaType == .video else { return }
        let go: Bool = lock.withLock {
            guard !stopped else { return false }
            decoding = true
            return true
        }
        guard go else { return }
        defer { lock.withLock { decoding = false } }
        decoder.decode(sampleBuffer) { [weak self] pixelBuffer in
            guard let self else { return }
            let frame = AiSeeFrame(pixelBuffer: pixelBuffer)
            let handler: (@Sendable (AiSeeFrame) -> Void)? = self.lock.withLock {
                guard !self.stopped else { return nil }
                self._latest = frame
                self.frames += 1
                return self.onFrame
            }
            handler?(frame)
        }
    }

    func stream(_ stream: LiveCaptureStream, didTerminateWith error: (any Error)?) {
        let text = error.map { "livestream: ended with error: \($0.localizedDescription)" } ?? "livestream: ended"
        log(text)
        // Errored or clean, this is an end of stream: it goes out on onTerminate
        // only, so the host isn't notified twice for one event.
        let terminate = lock.withLock { onTerminate }
        terminate?(error != nil ? text : nil)
    }
}
#endif
