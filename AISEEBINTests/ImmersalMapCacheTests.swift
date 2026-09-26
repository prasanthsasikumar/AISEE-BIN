import XCTest
@testable import AISEEBIN

/// The map binaries the native plugin loads, kept on disk per Immersal map id.
final class ImmersalMapCacheTests: XCTestCase {

    private var directory: URL!
    private var cache: ImmersalMapCache!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("immersal-cache-\(UUID().uuidString)")
        cache = ImmersalMapCache(directory: directory)
        TestURLStub.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        TestURLStub.reset()
        super.tearDown()
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLStub.self]
        return URLSession(configuration: configuration)
    }

    private func write(_ id: Int, bytes: Int = 4096) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: cache.url(for: id))
    }

    func testEmptyCacheIsMissingEverything() {
        XCTAssertEqual(cache.missing(from: [1, 2]), [1, 2])
        XCTAssertFalse(cache.contains(1))
        XCTAssertNil(cache.data(for: 1))
    }

    func testFileNamedByIDCountsAsCached() throws {
        try write(1)
        XCTAssertEqual(cache.url(for: 1).lastPathComponent, "1.bytes")
        XCTAssertTrue(cache.contains(1))
        XCTAssertEqual(cache.missing(from: [1, 2]), [2])
        XCTAssertEqual(cache.data(for: 1)?.count, 4096)
    }

    func testFetchWritesTheBodyAndAsksForEachID() async throws {
        TestURLStub.data = (200, Data(repeating: 0x5d, count: 2048))
        try await cache.fetch([5, 6], token: "tok", session: session())
        XCTAssertTrue(cache.contains(5))
        XCTAssertTrue(cache.contains(6))
        XCTAssertEqual(cache.data(for: 5)?.count, 2048)
        let queries = TestURLStub.requests.map { $0.query ?? "" }.sorted()
        XCTAssertEqual(queries, ["id=5&token=tok", "id=6&token=tok"])
        XCTAssertTrue(TestURLStub.requests.allSatisfy { $0.path == "/map" })
    }

    func testFetchRejectsImmersalJSONErrorAndWritesNothing() async {
        TestURLStub.stub = (200, #"{"error":"auth"}"#)
        do {
            try await cache.fetch([5], token: "tok", session: session())
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue("\(error)".contains("auth"), "\(error)")
        }
        XCTAssertFalse(cache.contains(5))
    }

    /// A captive portal or proxy answers 200 with an HTML page, easily over 1 KB.
    func testFetchRejectsAnHTMLPageAndWritesNothing() async {
        let page = "<!DOCTYPE html><html><body>" + String(repeating: "Sign in to the network. ", count: 100) + "</body></html>"
        TestURLStub.data = (200, Data(page.utf8))
        do {
            try await cache.fetch([5], token: "tok", session: session())
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue("\(error)".contains("not a map"), "\(error)")
        }
        XCTAssertFalse(cache.contains(5))
    }

    func testFetchRejectsHTTPErrorAndWritesNothing() async {
        TestURLStub.data = (404, Data(repeating: 1, count: 5000))
        do {
            try await cache.fetch([5], token: "tok", session: session())
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue("\(error)".contains("404"), "\(error)")
        }
        XCTAssertFalse(cache.contains(5))
    }

    @MainActor
    func testFetchReportsProgressPerMap() async throws {
        TestURLStub.data = (200, Data(repeating: 0x5d, count: 2048))
        let seen = Progress()
        try await cache.fetch([1, 2], token: "tok", session: session()) { seen.values.append($0) }
        XCTAssertEqual(seen.values, [0.5, 1.0])
    }

    func testRemoveAndPrune() throws {
        try write(1); try write(2); try write(3)
        cache.remove(3)
        XCTAssertFalse(cache.contains(3))
        cache.prune(keeping: [2])
        XCTAssertFalse(cache.contains(1))
        XCTAssertTrue(cache.contains(2))
    }

    @MainActor private final class Progress { var values: [Double] = [] }
}
