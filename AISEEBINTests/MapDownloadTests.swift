import XCTest
@testable import AISEEBIN

/// Serves a fixed body over `URLProtocol` with Range support, so download tests
/// never touch the network. Records peak concurrency and per-chunk attempts.
final class StubRangeServer: URLProtocol {

    struct Config {
        /// The whole object the stub serves.
        var body: Data
        /// When false the stub ignores `Range` and answers 200 with the whole body.
        var honoursRange = true
        /// Chunk start offsets that fail once before succeeding.
        var failOnceAtOffsets: Set<Int> = []
        /// Held before responding, so overlapping requests are observable.
        var delay: Duration = .milliseconds(40)
    }

    /// Shared mutable test state. Serialised by `lock`; tests set it before use.
    private static let lock = NSLock()
    private static var config = Config(body: Data())
    private static var inFlight = 0
    private static var peakInFlight = 0
    private static var attemptsByOffset: [Int: Int] = [:]

    static func install(_ config: Config) {
        lock.lock(); defer { lock.unlock() }
        self.config = config
        inFlight = 0
        peakInFlight = 0
        attemptsByOffset = [:]
    }

    static var peakConcurrency: Int {
        lock.lock(); defer { lock.unlock() }
        return peakInFlight
    }

    static func attempts(atOffset offset: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        return attemptsByOffset[offset] ?? 0
    }

    /// A session wired to this stub only.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubRangeServer.self]
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (body, honoursRange, failOnce, delay) = Self.snapshot()
        let rangeHeader = request.value(forHTTPHeaderField: "Range")

        // Parse "bytes=start-end"; absent or unhonoured means the whole object.
        var start = 0
        var end = body.count - 1
        if honoursRange, let rangeHeader,
           let spec = rangeHeader.split(separator: "=").last?.split(separator: "-"),
           let parsedStart = Int(spec.first ?? "") {
            start = parsedStart
            end = min(Int(spec.count > 1 ? spec[1] : "") ?? body.count - 1, body.count - 1)
        }

        let attempt = Self.beginRequest(offset: start)

        Task {
            try? await Task.sleep(for: delay)
            defer { Self.endRequest() }

            // A chunk marked flaky fails its first attempt only.
            if failOnce.contains(start) && attempt == 1 {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            guard start < body.count else {
                self.respond(status: 416, headers: [:], body: Data())
                return
            }

            if honoursRange && rangeHeader != nil {
                let slice = body.subdata(in: start..<(end + 1))
                self.respond(status: 206,
                             headers: ["Content-Range": "bytes \(start)-\(end)/\(body.count)",
                                       "Content-Length": "\(slice.count)"],
                             body: slice)
            } else {
                self.respond(status: 200, headers: ["Content-Length": "\(body.count)"], body: body)
            }
        }
    }

    private func respond(status: Int, headers: [String: String], body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    // MARK: Shared-state helpers

    private static func snapshot() -> (Data, Bool, Set<Int>, Duration) {
        lock.lock(); defer { lock.unlock() }
        return (config.body, config.honoursRange, config.failOnceAtOffsets, config.delay)
    }

    /// Registers a request as in flight and returns its attempt number for that offset.
    private static func beginRequest(offset: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        attemptsByOffset[offset, default: 0] += 1
        return attemptsByOffset[offset]!
    }

    private static func endRequest() {
        lock.lock(); defer { lock.unlock() }
        inFlight -= 1
    }
}

final class MapDownloadTests: XCTestCase {

    /// A body several chunks long, with a recognisable pattern per byte so a
    /// misordered reassembly fails rather than merely producing the right length.
    private func makeBody(chunks: Double) -> Data {
        let count = Int(Double(MapSyncService.downloadChunkSize) * chunks)
        var data = Data(capacity: count)
        for i in 0..<count { data.append(UInt8(truncatingIfNeeded: i &* 31 &+ 7)) }
        return data
    }

    private func service() -> MapSyncService {
        var service = MapSyncService()
        service.session = StubRangeServer.session()
        return service
    }

    func testDownloadReassemblesChunksInOrder() async throws {
        let body = makeBody(chunks: 3.5)
        StubRangeServer.install(.init(body: body))

        let data = try await service().download(path: "m/v1/world.arworldmap")

        XCTAssertEqual(data.count, body.count)
        XCTAssertEqual(data, body, "chunks must be reassembled in offset order")
    }

    func testDownloadFetchesChunksConcurrently() async throws {
        StubRangeServer.install(.init(body: makeBody(chunks: 6)))

        _ = try await service().download(path: "m/v1/world.arworldmap")

        XCTAssertGreaterThan(StubRangeServer.peakConcurrency, 1,
                             "chunks must be fetched in parallel, not one at a time")
        XCTAssertLessThanOrEqual(StubRangeServer.peakConcurrency, MapSyncService.downloadConcurrency,
                                 "must not exceed the configured concurrency")
    }

    func testDownloadRetriesOnlyTheFailedChunk() async throws {
        let body = makeBody(chunks: 3)
        let flakyOffset = MapSyncService.downloadChunkSize   // the second chunk
        StubRangeServer.install(.init(body: body, failOnceAtOffsets: [flakyOffset]))

        let data = try await service().download(path: "m/v1/world.arworldmap")

        XCTAssertEqual(data, body)
        XCTAssertEqual(StubRangeServer.attempts(atOffset: flakyOffset), 2, "failed chunk retried once")
        XCTAssertEqual(StubRangeServer.attempts(atOffset: 0), 1, "healthy chunks not re-fetched")
    }

    func testDownloadHandlesServerThatIgnoresRange() async throws {
        let body = makeBody(chunks: 2)
        StubRangeServer.install(.init(body: body, honoursRange: false))

        let data = try await service().download(path: "m/v1/world.arworldmap")

        XCTAssertEqual(data, body)
    }

    func testDownloadDecompressesGzippedObjectsTransparently() async throws {
        let original = makeBody(chunks: 2.5)
        StubRangeServer.install(.init(body: GzipCodec.compress(original)))

        let data = try await service().download(path: "m/v1/world.arworldmap.gz")

        XCTAssertEqual(data, original, "a .gz path must arrive at the caller already inflated")
    }

    func testDownloadLeavesUncompressedObjectsAlone() async throws {
        // Bytes that happen to start with the gzip magic must still pass through
        // untouched when the path does not claim to be compressed.
        var body = Data([0x1f, 0x8b, 0x08, 0x00])
        body.append(makeBody(chunks: 1.2))
        StubRangeServer.install(.init(body: body))

        let data = try await service().download(path: "default/v2/greenhouse.arworldmap")

        XCTAssertEqual(data, body)
    }

    func testDownloadSurfacesACorruptGzipRatherThanReturningGarbage() async throws {
        var corrupt = GzipCodec.compress(makeBody(chunks: 1.5))
        corrupt[corrupt.count - 5] ^= 0xFF          // break the stored CRC
        StubRangeServer.install(.init(body: corrupt))

        do {
            _ = try await service().download(path: "m/v1/world.arworldmap.gz")
            XCTFail("a corrupt archive must throw, not yield partial bytes")
        } catch {
            XCTAssertEqual(error as? GzipCodec.Failure, .corrupt)
        }
    }

    func testDownloadReportsProgressEndingAtOne() async throws {
        let body = makeBody(chunks: 4)
        StubRangeServer.install(.init(body: body))

        let fractions = Locked<[Double]>([])
        let data = try await service().download(path: "m/v1/world.arworldmap") { progress in
            fractions.withLock { $0.append(progress.fraction) }
        }

        XCTAssertEqual(data.count, body.count)
        let seen = fractions.withLock { $0 }
        XCTAssertEqual(try XCTUnwrap(seen.last), 1, accuracy: 0.0001, "progress must finish at 1")
        XCTAssertTrue(seen.allSatisfy { $0 >= 0 && $0 <= 1 }, "progress stays within 0…1")
        XCTAssertEqual(seen, seen.sorted(), "progress must not go backwards")
    }
}

/// Minimal lock box, so a progress callback can accumulate across actors.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
