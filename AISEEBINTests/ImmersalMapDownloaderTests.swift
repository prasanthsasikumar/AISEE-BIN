import XCTest
@testable import AISEEBIN

/// Filling the map cache from the app: once per id per launch, one download at
/// a time. The loop this guards against: a cached file the plugin refuses is
/// deleted, re-downloaded, refused again, and positioning restarts forever.
@MainActor
final class ImmersalMapDownloaderTests: XCTestCase {

    private var directory: URL!
    private var cache: ImmersalMapCache!
    private var downloader: ImmersalMapDownloader!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("immersal-downloader-\(UUID().uuidString)")
        cache = ImmersalMapCache(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLStub.self]
        downloader = ImmersalMapDownloader(cache: cache, session: URLSession(configuration: configuration))
        TestURLStub.reset()
        TestURLStub.data = (200, Data(repeating: 0x5d, count: 2048))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        TestURLStub.reset()
        super.tearDown()
    }

    func testFetchesMissingMapsAndReportsAllCached() async {
        let complete = await downloader.ensure(ids: [1, 2], token: "t")
        XCTAssertTrue(complete)
        XCTAssertTrue(cache.contains(1))
        XCTAssertTrue(cache.contains(2))
        XCTAssertEqual(TestURLStub.requests.count, 2)
        XCTAssertEqual(downloader.state, "on device")
    }

    func testAnIDAlreadyFetchedThisLaunchIsNeverFetchedAgain() async {
        _ = await downloader.ensure(ids: [1], token: "t")
        cache.remove(1)   // what the factory does to a file the plugin refuses
        let complete = await downloader.ensure(ids: [1], token: "t")
        XCTAssertFalse(complete)
        XCTAssertEqual(TestURLStub.requests.count, 1, "no second download in the same launch")
        XCTAssertFalse(cache.contains(1))
        XCTAssertTrue(downloader.state?.contains("refused") == true, downloader.state ?? "nil")
    }

    func testConcurrentCallsShareOneDownload() async {
        async let a = downloader.ensure(ids: [1], token: "t")
        async let b = downloader.ensure(ids: [1], token: "t")
        let results = await [a, b]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(TestURLStub.requests.count, 1)
    }

    func testNothingToDoWhenAllCached() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: cache.url(for: 1))
        let complete = await downloader.ensure(ids: [1], token: "t")
        XCTAssertTrue(complete)
        XCTAssertEqual(TestURLStub.requests.count, 0)
    }

    func testMissingTokenIsReportedNotAttempted() async {
        let complete = await downloader.ensure(ids: [1], token: "")
        XCTAssertFalse(complete)
        XCTAssertEqual(downloader.state, "no token")
        XCTAssertEqual(TestURLStub.requests.count, 0)
    }

    func testFailureLeavesCloudReasonAndDoesNotRetryThisLaunch() async {
        TestURLStub.data = (404, Data(repeating: 1, count: 5000))
        let first = await downloader.ensure(ids: [1], token: "t")
        XCTAssertFalse(first)
        XCTAssertTrue(downloader.state?.hasPrefix("cloud (") == true, downloader.state ?? "nil")
        TestURLStub.data = (200, Data(repeating: 0x5d, count: 2048))
        let second = await downloader.ensure(ids: [1], token: "t")
        XCTAssertFalse(second)
        XCTAssertEqual(TestURLStub.requests.count, 1)
    }
}
