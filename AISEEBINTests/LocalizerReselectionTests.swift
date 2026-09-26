import XCTest
@testable import AISEEBIN

/// When a map binary lands mid-session the running localizer is swapped in
/// place: the anchor, the attempt counters and the session stay as they were.
@MainActor
final class LocalizerReselectionTests: XCTestCase {

    private var savedToken = ""

    override func setUp() {
        super.setUp()
        // Glasses positioning refuses to start without a token; the test host has none bundled.
        savedToken = ImmersalConfig.storedToken
        ImmersalConfig.token = "test-token"
    }

    override func tearDown() {
        ImmersalConfig.token = savedToken
        super.tearDown()
    }

    private func waitForName(_ read: @escaping () -> String) async -> String {
        for _ in 0..<100 {
            if !read().isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return read()
    }

    func testPhoneLocalizerSelectsOffTheMainActorAndReselectsWithoutResetting() async {
        let phone = PhoneImmersalLocalizer()
        phone.start(alignment: .identity(mapID: 424242, origin: nil))
        XCTAssertTrue(phone.running)
        let first = await waitForName { phone.localizerName }
        XCTAssertEqual(first, "cloud", "the simulator has no plugin, so the cloud is chosen")

        phone.reselectLocalizer()
        let again = await waitForName { phone.localizerName }
        XCTAssertEqual(again, "cloud")
        XCTAssertTrue(phone.running, "reselection never stops positioning")
        XCTAssertEqual(phone.attempts, 0)
        phone.stop()
    }

    func testGlassesPositioningReselectsWithoutResetting() async {
        let glasses = GlassesPositioning(pedometer: ScriptedDistance())
        glasses.start(alignment: .identity(mapID: 424242, origin: nil))
        XCTAssertTrue(glasses.isRunning)
        let first = await waitForName { glasses.localizerName }
        XCTAssertEqual(first, "cloud")

        glasses.reselectLocalizer()
        let again = await waitForName { glasses.localizerName }
        XCTAssertEqual(again, "cloud")
        XCTAssertTrue(glasses.isRunning)
        XCTAssertEqual(glasses.fixes, 0)
        glasses.stop()
    }

    private final class ScriptedDistance: WalkedDistanceSource, @unchecked Sendable {
        var walkedMetres: Float = 0
        func start() {}
        func stop() {}
    }
}
