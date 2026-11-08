import XCTest
@testable import AISEEBIN

/// The usage log's core: sequence numbers, the on-disk queue surviving failed
/// uploads and restarts, idempotent retries, session boundaries, and the
/// unclean-exit marker.
final class UsageLogTests: XCTestCase {

    /// Records what it was asked to upload; throws while `failing` is set.
    final class FakeUploader: UsageUploading, @unchecked Sendable {
        private let lock = NSLock()
        private var _sessions: [SessionHeader] = []
        private var _events: [QueuedEvent] = []
        var failing = false

        var sessions: [SessionHeader] { lock.withLock { _sessions } }
        var events: [QueuedEvent] { lock.withLock { _events } }

        func upload(sessions: [SessionHeader], events: [QueuedEvent]) async throws {
            if lock.withLock({ failing }) { throw URLError(.notConnectedToInternet) }
            lock.withLock { _sessions += sessions; _events += events }
        }
    }

    private var directory: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
        TestURLStub.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        TestURLStub.reset()
        super.tearDown()
    }

    private func header(_ id: UUID = UUID()) -> SessionHeader {
        SessionHeader(session_id: id, install_id: "install", platform: "ios", device: "test", os_version: "17.0",
                      app_version: "1.0 (1)", build_config: "debug", simulator: true, staff: false, started_at: clock)
    }

    private func makeLog(_ uploader: UsageUploading, header: SessionHeader? = nil,
                         staff: (() -> Bool)? = nil) -> UsageLog {
        UsageLog(directory: directory, uploader: uploader, now: { [unowned self] in self.clock },
                 header: header ?? self.header(), staff: staff)
    }

    /// What is still on disk, oldest first.
    private func queued() -> [Data] { (try? UsageQueue(directory: directory).peekBatch(max: 100)) ?? [] }

    private func stubbedUploader() -> UsageUploader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLStub.self]
        return UsageUploader(session: URLSession(configuration: configuration))
    }

    func testSeqIsMonotonicAndTypesRecorded() async {
        let uploader = FakeUploader()
        let log = makeLog(uploader)
        log.appDidLaunch()
        log.log("map.loaded", ["slug": "x", "ms": 12])
        log.log("mode.enter", ["mode": "Navigate"])
        log.log("beacon", ["on": true])
        await log.flush()

        XCTAssertEqual(uploader.events.map(\.seq), [0, 1, 2, 3])
        XCTAssertEqual(uploader.events.map(\.type), ["app.launch", "map.loaded", "mode.enter", "beacon"])
        XCTAssertEqual(uploader.events[1].data, ["slug": .string("x"), "ms": .number(12)])
        XCTAssertEqual(uploader.sessions.map(\.session_id), [log.sessionID])
        XCTAssertTrue(uploader.events.allSatisfy { $0.session_id == log.sessionID })
        XCTAssertEqual(uploader.events[0].t, "2027-01-15T08:00:00.000Z")
    }

    func testQueueSurvivesReopen() async {
        let failing = FakeUploader()
        failing.failing = true
        let first = makeLog(failing)
        first.log("a")
        first.log("b")
        await first.flush()
        XCTAssertTrue(failing.events.isEmpty)

        let working = FakeUploader()
        let second = makeLog(working)
        await second.flush()
        XCTAssertEqual(working.events.map(\.type), ["a", "b"])
        XCTAssertEqual(working.sessions.map(\.session_id), [first.sessionID])

        await second.flush()
        XCTAssertEqual(working.events.count, 2, "delivered once")
    }

    func testFailedUploadKeepsBatch() async {
        let log = makeLog(stubbedUploader())
        log.log("a")
        log.log("b")
        log.log("c")

        TestURLStub.stub = (500, "boom")
        await log.flush()
        // One header line plus three events still on disk.
        XCTAssertEqual(queued().count, 4)

        TestURLStub.stub = (201, "")
        await log.flush()
        XCTAssertTrue(queued().isEmpty)
    }

    func testRetryIsIdempotent() async {
        let log = makeLog(stubbedUploader())
        log.log("a")
        TestURLStub.stub = (201, "")
        await log.flush()

        let requests = TestURLStub.urlRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url!.absoluteString.contains("rest/v1/ab_sessions?on_conflict=session_id"))
        XCTAssertTrue(requests[1].url!.absoluteString.contains("rest/v1/ab_events?on_conflict=session_id,seq"))
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") ?? false)
            XCTAssertNotNil(request.value(forHTTPHeaderField: "apikey"))
        }
    }

    func testRejectedBatchIsDroppedSoLaterEventsFlow() async {
        let log = makeLog(stubbedUploader())
        log.log("bad")
        TestURLStub.stub = (400, "invalid input")
        await log.flush()
        XCTAssertTrue(queued().isEmpty, "a permanent 4xx drops the batch")

        log.log("good")
        TestURLStub.reset()
        TestURLStub.stub = (201, "")
        await log.flush()
        XCTAssertEqual(TestURLStub.urlRequests.count, 1, "only the new event, no retry of the rejected batch")
        XCTAssertTrue(TestURLStub.urlRequests[0].url!.absoluteString.contains("ab_events"))
        XCTAssertTrue(queued().isEmpty)
    }

    func testRetryableErrorsKeepBatch() async {
        let log = makeLog(stubbedUploader())
        log.log("a")
        for status in [408, 429, 503] {
            TestURLStub.stub = (status, "")
            await log.flush()
            XCTAssertEqual(queued().count, 2, "status \(status)")
        }
    }

    func testQueueCapDropsOldestLines() async {
        let failing = FakeUploader()
        failing.failing = true
        let log = UsageLog(directory: directory, uploader: failing, now: { [unowned self] in self.clock },
                           header: header(), maxQueueLines: 5)
        for i in 0..<10 { log.log("e\(i)") }
        await log.flush()

        let working = FakeUploader()
        let reopened = makeLog(working)
        await reopened.flush()
        XCTAssertEqual(working.events.map(\.type), ["e5", "e6", "e7", "e8", "e9"])
        XCTAssertEqual(UsageLog.maxQueueLines, 200_000)
    }

    func testNewSessionAfterLongBackground() async {
        let uploader = FakeUploader()
        let log = makeLog(uploader)
        log.appDidLaunch()
        let first = log.sessionID

        log.appDidEnterBackground()
        clock += 299
        log.appDidEnterForeground()
        XCTAssertEqual(log.sessionID, first)

        log.appDidEnterBackground()
        clock += 301
        log.appDidEnterForeground()
        let second = log.sessionID
        XCTAssertNotEqual(second, first)
        log.log("x")
        await log.flush()

        let firstEvents = uploader.events.filter { $0.session_id == first }
        XCTAssertEqual(firstEvents.map(\.type), ["app.launch", "app.background", "app.foreground", "app.background"])
        XCTAssertEqual(firstEvents.map(\.seq), [0, 1, 2, 3])
        let secondEvents = uploader.events.filter { $0.session_id == second }
        XCTAssertEqual(secondEvents.map(\.type), ["app.foreground", "x"])
        XCTAssertEqual(secondEvents.map(\.seq), [0, 1])
        XCTAssertEqual(Set(uploader.sessions.map(\.session_id)), [first, second])
        XCTAssertEqual(uploader.sessions.first { $0.session_id == second }?.started_at, clock)
    }

    func testUncleanExitReported() async {
        let firstUploader = FakeUploader()
        let firstLog = makeLog(firstUploader)
        firstLog.appDidLaunch()
        await firstLog.flush()
        let first = firstLog.sessionID
        XCTAssertEqual(firstUploader.events.first?.data["unclean_previous"], .null)

        let uploader = FakeUploader()
        let second = makeLog(uploader)
        second.appDidLaunch()
        await second.flush()

        XCTAssertEqual(uploader.events.first { $0.session_id == second.sessionID }?.data["unclean_previous"],
                       .string(first.uuidString.lowercased()))
    }

    func testCleanExitNotReported() async {
        // The first log's background flush runs on its own and would otherwise
        // race the second log for the shared queue file; failing, it drops nothing.
        let failing = FakeUploader()
        failing.failing = true
        let firstLog = makeLog(failing)
        firstLog.appDidLaunch()
        firstLog.appDidEnterBackground()
        _ = firstLog.sessionID

        let uploader = FakeUploader()
        let second = makeLog(uploader)
        second.appDidLaunch()
        await second.flush()
        XCTAssertEqual(uploader.events.first { $0.session_id == second.sessionID }?.data["unclean_previous"], .null)
    }

    func testValueEncoding() throws {
        let long = String(repeating: "a", count: 5_000)
        let value: UsageValue = ["nan": .number(.nan), "inf": .number(.infinity), "s": .string(long),
                                 "n": 1.5, "i": 3, "b": false, "a": ["x", nil]]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        XCTAssertTrue(json["nan"] is NSNull)
        XCTAssertTrue(json["inf"] is NSNull)
        XCTAssertEqual((json["s"] as! String).count, 4_000)
        XCTAssertEqual(json["n"] as? Double, 1.5)
        XCTAssertEqual(json["i"] as? Int, 3)
        XCTAssertEqual(json["b"] as? Bool, false)
        XCTAssertEqual((json["a"] as! [Any]).count, 2)

        let nul = try JSONSerialization.jsonObject(with: JSONEncoder().encode(UsageValue.string("a\u{0}b")),
                                                   options: .fragmentsAllowed) as? String
        XCTAssertEqual(nul, "ab", "Postgres rejects NUL in text and jsonb")

        let decoded = try JSONDecoder().decode(UsageValue.self, from: JSONEncoder().encode(["k": UsageValue.string("v")]))
        XCTAssertEqual(decoded, .object(["k": .string("v")]))
    }

    // MARK: - New sessions

    func testNewSessionHookRelogsContextRightAfterForeground() async {
        let uploader = FakeUploader()
        let log = makeLog(uploader)
        var calls = 0
        log.onNewSession = {
            calls += 1
            log.log("map.loaded", ["slug": "dome", "source": "cache", "ms": 0])
            log.log("mode.enter", ["mode": "Navigate"])
        }
        log.appDidLaunch()
        log.appDidEnterBackground()
        clock += 10
        log.appDidEnterForeground()
        XCTAssertEqual(calls, 0, "not at launch, not after a short background")

        log.appDidEnterBackground()
        clock += 301
        log.appDidEnterForeground()
        log.log("pose", ["x": 1, "z": 2])
        XCTAssertEqual(calls, 1)
        await log.flush()

        let second = uploader.events.filter { $0.session_id == log.sessionID }
        XCTAssertEqual(second.map(\.type), ["app.foreground", "map.loaded", "mode.enter", "pose"])
        XCTAssertEqual(second.map(\.seq), [0, 1, 2, 3])
        XCTAssertEqual(second[1].data["slug"], "dome")
    }

    func testStaffFlagReadForEachNewSession() async {
        let uploader = FakeUploader()
        var staff = false
        let first = SessionHeader(session_id: UUID(), install_id: "install", platform: "ios", device: "test",
                                  os_version: "17.0", app_version: "1.0 (1)", build_config: "debug",
                                  simulator: true, staff: true, started_at: clock)
        let log = makeLog(uploader, header: first, staff: { staff })
        log.appDidLaunch()
        let firstID = log.sessionID
        log.appDidEnterBackground()
        staff = false
        clock += 301
        log.appDidEnterForeground()
        let secondID = log.sessionID
        log.appDidEnterBackground()
        staff = true
        clock += 301
        log.appDidEnterForeground()
        let thirdID = log.sessionID
        await log.flush()

        let byID = Dictionary(uniqueKeysWithValues: uploader.sessions.map { ($0.session_id, $0.staff) })
        XCTAssertEqual(byID[firstID], true, "the first header as given")
        XCTAssertEqual(byID[secondID], false)
        XCTAssertEqual(byID[thirdID], true)
    }

    func testCurrentHeaderReadsStoredStaffFlag() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SessionHeader.staffDefaultsKey)
        defer { defaults.set(saved, forKey: SessionHeader.staffDefaultsKey) }
        defaults.set(true, forKey: SessionHeader.staffDefaultsKey)
        XCTAssertTrue(SessionHeader.current().staff)
        defaults.set(false, forKey: SessionHeader.staffDefaultsKey)
        XCTAssertFalse(SessionHeader.current().staff)
        XCTAssertEqual(SessionHeader.staffDefaultsKey, "staff.mode")
    }

    // MARK: - Queue

    private func line(_ i: Int) -> Data { Data("{\"i\":\(i),\"pad\":\"\(String(repeating: "x", count: 40))\"}".utf8) }
    private func index(_ data: Data) -> Int {
        (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["i"] as! Int
    }

    func testLargeBacklogDrainsWithFewRewrites() throws {
        var compactions = 0
        let queue = UsageQueue(directory: directory, onCompact: { compactions += 1 })
        for i in 0..<20_000 { try queue.append(line(i)) }
        var seen: [Int] = []
        while true {
            let batch = try queue.peekBatch(max: UsageLog.batchSize)
            if batch.isEmpty { break }
            seen += batch.map(index)
            try queue.drop(count: batch.count)
        }
        XCTAssertEqual(seen, Array(0..<20_000))
        XCTAssertLessThanOrEqual(compactions, 8, "40 batches, file rewritten only when over half consumed")
        XCTAssertGreaterThan(compactions, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.offsetFile.path))
    }

    func testOffsetAndCompactionSurviveReopen() throws {
        var compactions = 0
        let first = UsageQueue(directory: directory, onCompact: { compactions += 1 })
        for i in 0..<10 { try first.append(line(i)) }
        let size = try FileManager.default.attributesOfItem(atPath: first.file.path)[.size] as! NSNumber
        try first.drop(count: 3)
        XCTAssertEqual(compactions, 0, "under half consumed: only the offset moves")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.offsetFile.path))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: first.file.path)[.size] as! NSNumber), size,
                       "file not rewritten")

        let second = UsageQueue(directory: directory, onCompact: { compactions += 1 })
        XCTAssertEqual(try second.peekBatch(max: 100).map(index), Array(3..<10))
        try second.drop(count: 3)
        XCTAssertEqual(compactions, 1, "over half consumed: compacted")
        XCTAssertEqual(try String(contentsOf: second.offsetFile, encoding: .utf8), "0")

        let third = UsageQueue(directory: directory)
        XCTAssertEqual(try third.peekBatch(max: 100).map(index), Array(6..<10))
        try third.append(line(10))
        XCTAssertEqual(try third.peekBatch(max: 100).map(index), Array(6..<11))
    }

    func testCapTrimMovesOffset() throws {
        let queue = UsageQueue(directory: directory)
        for i in 0..<100 { try queue.append(line(i)) }
        XCTAssertEqual(try queue.trim(keepingLast: 60), 40)
        XCTAssertEqual(try queue.peekBatch(max: 1000).map(index), Array(40..<100))
        XCTAssertEqual(try queue.trim(keepingLast: 60), 0)
    }

    func testReadErrorNeverEmptiesTheQueue() throws {
        let queue = UsageQueue(directory: directory)
        for i in 0..<3 { try queue.append(line(i)) }
        let before = try Data(contentsOf: queue.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queue.file.path)
        XCTAssertThrowsError(try queue.drop(count: 1))
        XCTAssertThrowsError(try queue.peekBatch(max: 10))
        XCTAssertThrowsError(try queue.trim(keepingLast: 0))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queue.file.path)
        XCTAssertEqual(try Data(contentsOf: queue.file), before, "queue untouched by the failed reads")
        XCTAssertEqual(try queue.peekBatch(max: 10).count, 3)
    }

    func testAppendNeverReplacesAnExistingQueue() throws {
        let queue = UsageQueue(directory: directory)
        for i in 0..<3 { try queue.append(line(i)) }
        let before = try Data(contentsOf: queue.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: queue.file.path)
        XCTAssertThrowsError(try queue.append(line(3)), "an existing file that cannot be opened is an error, not a rewrite")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queue.file.path)
        XCTAssertEqual(try Data(contentsOf: queue.file), before)
    }

    func testAppendAfterCrashStartsOnFreshLine() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = UsageQueue(directory: directory)
        try Data("{\"i\":0}\n{\"i\":1,\"trunc".utf8).write(to: queue.file)
        try queue.append(line(2))
        let lines = try queue.peekBatch(max: 10)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(data: lines[1], encoding: .utf8), "{\"i\":1,\"trunc")
        XCTAssertEqual(index(lines[2]), 2, "the new line is whole")
    }

    func testStaleOffsetIgnoredForNewFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = UsageQueue(directory: directory)
        try Data("999".utf8).write(to: queue.offsetFile)
        try queue.append(line(0))
        XCTAssertEqual(try queue.peekBatch(max: 10).map(index), [0])
    }
}
