import XCTest
@testable import AISEEBIN

/// Which localizer a positioning start gets, and why. On the simulator the
/// native stubs refuse every map, which is the "corrupt cached file" case.
final class ImmersalLocalizerFactoryTests: XCTestCase {

    private var directory: URL!
    private var cache: ImmersalMapCache!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("immersal-factory-\(UUID().uuidString)")
        cache = ImmersalMapCache(directory: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ id: Int) throws {
        try Data(repeating: 1, count: 4096).write(to: cache.url(for: id))
    }

    func testCloudWhenThePluginIsUnavailable() throws {
        try write(1)
        let choice = ImmersalLocalizerFactory.make(mapIDs: [1], token: "t", cache: cache,
                                                   native: ImmersalNative(), nativeAvailable: false)
        XCTAssertEqual(choice.localizer.name, "cloud")
        XCTAssertTrue(choice.reason.contains("plugin unavailable"), choice.reason)
        XCTAssertTrue(cache.contains(1), "an unavailable plugin is no reason to drop a good file")
    }

    func testCloudWhenAnyMapIsMissingNamesTheMissingOne() throws {
        try write(1)
        let choice = ImmersalLocalizerFactory.make(mapIDs: [1, 2], token: "t", cache: cache,
                                                   native: ImmersalNative(), nativeAvailable: true)
        XCTAssertEqual(choice.localizer.name, "cloud")
        XCTAssertTrue(choice.reason.contains("2 not cached"), choice.reason)
        XCTAssertFalse(choice.reason.contains("1 not cached"), choice.reason)
    }

    func testCloudAndFileRemovedWhenTheMapDoesNotLoad() throws {
        try write(1)
        let native = ImmersalNative()   // simulator stubs: every load fails
        let choice = ImmersalLocalizerFactory.make(mapIDs: [1], token: "t", cache: cache,
                                                   native: native, nativeAvailable: true)
        XCTAssertEqual(choice.localizer.name, "cloud")
        XCTAssertTrue(choice.reason.contains("1 load failed"), choice.reason)
        XCTAssertFalse(cache.contains(1), "a file the plugin refuses is re-fetched next time online")
        XCTAssertEqual(native.loadedMapIDs, [])
    }

    func testCloudLocalizerCarriesTheMapIDs() {
        let choice = ImmersalLocalizerFactory.make(mapIDs: [7, 8], token: "t", cache: cache,
                                                   native: ImmersalNative(), nativeAvailable: false)
        let cloud = choice.localizer as? CloudImmersalLocalizer
        XCTAssertEqual(cloud?.mapIDs, [7, 8])
        XCTAssertEqual(cloud?.token, "t")
    }
}
