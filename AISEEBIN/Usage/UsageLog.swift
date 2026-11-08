import Foundation
import UIKit
import os

/// What view models and services log through, so tests can inject a fake.
protocol UsageLogging {
    func log(_ type: String, _ data: [String: UsageValue])
}

/// Records what happens in the app as numbered events per session and uploads
/// them to `ab_sessions` / `ab_events` in batches.
///
/// A session runs from launch to background or terminate; coming back after more
/// than `sessionTimeout` in the background starts a new one. Each session's
/// events are numbered from 0. Every call is fire-and-forget: state and disk I/O
/// live on one serial queue, uploads run in tasks, and nothing throws to callers.
///
/// Never writes to `DiagnosticsLog`: that log mirrors into this one, so its own
/// errors go to `os.Logger` instead.
final class UsageLog: UsageLogging, @unchecked Sendable {
    static let shared = UsageLog(directory: UsageQueue.defaultDirectory, uploader: UsageUploader(),
                                 now: Date.init, header: .current())

    static let sessionTimeout: TimeInterval = 300
    static let batchSize = 500
    static let flushInterval: TimeInterval = 30

    private let queue = DispatchQueue(label: "com.flowsxr.aiseebin.usage")
    private let store: UsageQueue
    private let uploader: UsageUploading
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.flowsxr.aiseebin", category: "usage")
    private var marker: URL { store.directory.appendingPathComponent("running") }

    // Guarded by `queue`.
    private let template: SessionHeader
    private var session: SessionHeader
    private var headerQueued = false
    private var nextSeq = 0
    private var foregroundSince: Date
    private var backgroundSince: Date?
    private var timer: DispatchSourceTimer?

    // Guarded by `flushLock`.
    private let flushLock = NSLock()
    private var lastFlush: Task<Void, Never>?

    /// `header` describes the first session; later sessions copy it with a fresh
    /// id and start time.
    init(directory: URL, uploader: UsageUploading, now: @escaping () -> Date, header: SessionHeader) {
        store = UsageQueue(directory: directory)
        self.uploader = uploader
        self.now = now
        template = header
        session = header
        foregroundSince = now()
    }

    deinit { timer?.cancel() }

    var sessionID: UUID { queue.sync { session.session_id } }

    func log(_ type: String, _ data: [String: UsageValue] = [:]) {
        let t = now()
        queue.async { self.record(type, data, at: t) }
    }

    func appDidLaunch() {
        let t = now()
        queue.async {
            let previous = (try? String(contentsOf: self.marker, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.foregroundSince = t
            self.backgroundSince = nil
            self.writeMarker()
            self.record("app.launch", ["unclean_previous": previous.map { .string($0) } ?? .null], at: t)
            self.startTimer()
        }
        Task { await flush() }
    }

    /// Logs `app.foreground` after a real trip to the background (the first
    /// `.active` at launch is not one), starting a new session after a long one.
    func appDidEnterForeground() {
        let t = now()
        queue.async {
            if let since = self.backgroundSince {
                if t.timeIntervalSince(since) > Self.sessionTimeout { self.startSession(at: t) }
                self.foregroundSince = t
                self.backgroundSince = nil
                self.record("app.foreground", [:], at: t)
            }
            self.writeMarker()
            self.startTimer()
        }
    }

    func appDidEnterBackground() {
        let t = now()
        queue.async {
            guard self.backgroundSince == nil else { return }
            self.record("app.background", ["seconds_active": .number(t.timeIntervalSince(self.foregroundSince).rounded())], at: t)
            self.backgroundSince = t
            self.stopTimer()
            self.removeMarker()
        }
        Task { @MainActor in
            let task = BackgroundTask(name: "usage-flush")
            await self.flush()
            task.end()
        }
    }

    func appWillTerminate() {
        let t = now()
        queue.sync {
            self.record("app.terminate", [:], at: t)
            self.stopTimer()
            self.removeMarker()
        }
    }

    /// Uploads everything queued so far, oldest first, in batches. Flushes run
    /// one after another; a failed batch stays on disk for the next flush.
    func flush() async {
        let task: Task<Void, Never> = flushLock.withLock {
            let previous = lastFlush
            let task = Task { await previous?.value; await self.drain() }
            lastFlush = task
            return task
        }
        await task.value
    }

    // MARK: - On `queue`

    private func record(_ type: String, _ data: [String: UsageValue], at t: Date) {
        if !headerQueued {
            append(QueueLine(session: session))
            headerQueued = true
        }
        append(QueueLine(event: QueuedEvent(session_id: session.session_id, seq: nextSeq,
                                            t: Self.timestamp(t), type: type, data: data)))
        nextSeq += 1
    }

    private func startSession(at t: Date) {
        session = template
        session.session_id = UUID()
        session.started_at = t
        headerQueued = false
        nextSeq = 0
    }

    private func append(_ line: QueueLine) {
        do { try store.append(JSONEncoder().encode(line)) }
        catch { logger.error("usage queue append failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func writeMarker() {
        do {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try Data(session.session_id.uuidString.lowercased().utf8).write(to: marker, options: .atomic)
        } catch { logger.error("usage marker write failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func removeMarker() { try? FileManager.default.removeItem(at: marker) }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.flush() }
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Upload

    private func drain() async {
        while true {
            let batch = await onQueue { self.store.peekBatch(max: Self.batchSize) }
            if batch.isEmpty { return }
            var sessions: [SessionHeader] = []
            var events: [QueuedEvent] = []
            let decoder = JSONDecoder()
            for data in batch {
                guard let line = try? decoder.decode(QueueLine.self, from: data) else {
                    logger.error("usage queue: dropping unreadable line")
                    continue
                }
                if let header = line.session { sessions.append(header) }
                if let event = line.event { events.append(event) }
            }
            do {
                try await uploader.upload(sessions: sessions, events: events)
            } catch {
                logger.error("usage upload failed, keeping \(batch.count) lines: \(error.localizedDescription, privacy: .public)")
                return
            }
            await onQueue {
                do { try self.store.drop(count: batch.count) }
                catch { self.logger.error("usage queue drop failed: \(error.localizedDescription, privacy: .public)") }
            }
            if batch.count < Self.batchSize { return }
        }
    }

    /// Runs `body` on `queue` after everything already scheduled there.
    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }

    // MARK: - Formatting

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// ISO 8601, UTC, milliseconds: `2026-11-07T08:00:00.000Z`.
    static func timestamp(_ date: Date) -> String { formatter.string(from: date) }
}

/// One line of the on-disk queue: a session header or an event (exactly one set).
private struct QueueLine: Codable {
    var session: SessionHeader?
    var event: QueuedEvent?
}

/// Keeps the app alive long enough to upload after it leaves the foreground.
@MainActor
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

extension SessionHeader {
    /// This device and build, starting now with a fresh session id.
    static func current() -> SessionHeader {
        #if DEBUG
        let config = "debug"
        #else
        let config = "release"
        #endif
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return SessionHeader(session_id: UUID(), install_id: ExploreConfig.installID, platform: "ios",
                             device: FieldTestClient.deviceName, os_version: UIDevice.current.systemVersion,
                             app_version: FieldTestClient.appVersion, build_config: config,
                             simulator: simulator, staff: false, started_at: Date())
    }
}
