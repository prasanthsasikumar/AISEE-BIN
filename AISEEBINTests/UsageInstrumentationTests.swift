import XCTest
@testable import AISEEBIN

/// The app's hook points call the usage log with the catalogue's event names.
@MainActor
final class UsageInstrumentationTests: XCTestCase {

    final class FakeUsage: UsageLogging, @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [(type: String, data: [String: UsageValue])] = []
        var events: [(type: String, data: [String: UsageValue])] { lock.withLock { _events } }
        func log(_ type: String, _ data: [String: UsageValue]) { lock.withLock { _events.append((type, data)) } }
        func types() -> [String] { events.map(\.type) }
    }

    func testModeChangeLogsLeaveAndEnter() {
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map)
        vm.mode = .navigation
        let fake = FakeUsage()
        vm.usage = fake
        vm.mode = .explore
        XCTAssertEqual(fake.types(), ["mode.leave", "mode.enter"])
        XCTAssertEqual(fake.events[0].data["mode"], "Navigate")
        XCTAssertNotNil(fake.events[0].data["seconds"])
        XCTAssertEqual(fake.events[1].data["mode"], "Explore")
    }

    func testStaffUnlockAndExitLogged() {
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map)
        let fake = FakeUsage()
        vm.usage = fake
        vm.unlockStaff()
        vm.exitStaffMode()
        XCTAssertTrue(fake.types().contains("staff.unlock"))
        XCTAssertTrue(fake.types().contains("staff.exit"))
        UserDefaults.standard.removeObject(forKey: "staff.mode")
    }

    func testDiagnosticsLogMirrorsToUsage() {
        let fake = FakeUsage()
        let saved = DiagnosticsLog.usage
        DiagnosticsLog.usage = fake
        defer { DiagnosticsLog.usage = saved }
        DiagnosticsLog.write("x")
        XCTAssertEqual(fake.types(), ["diag"])
        XCTAssertEqual(fake.events[0].data["line"], "x")
    }

    func testSettingLogsOldAndNew() {
        let fake = FakeUsage()
        fake.logSetting("speaking_rate", old: "normal", new: "faster")
        fake.logSetting("speaking_rate", old: "normal", new: "normal")
        XCTAssertEqual(fake.events.count, 1)
        XCTAssertEqual(fake.events[0].data["key"], "speaking_rate")
        XCTAssertEqual(fake.events[0].data["old"], "normal")
        XCTAssertEqual(fake.events[0].data["new"], "faster")
    }

    func testSecretSettingNeverLogsValue() {
        let fake = FakeUsage()
        fake.logSetting("immersal_token", old: "", new: "abc123secret", secret: true)
        XCTAssertEqual(fake.events[0].data["old"], "empty")
        XCTAssertEqual(fake.events[0].data["new"], "set")
        XCTAssertFalse(String(describing: fake.events[0].data).contains("abc123"))
    }

    func testBeaconSettingChangeLogged() {
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map)
        let fake = FakeUsage()
        let was = vm.beaconEnabled
        vm.usage = fake
        vm.beaconEnabled = !was
        XCTAssertEqual(fake.types(), ["settings.changed"])
        XCTAssertEqual(fake.events[0].data["key"], "beep_guidance")
        vm.beaconEnabled = was
    }
}
