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
        func clear() { lock.withLock { _events.removeAll() } }
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

    func testLaunchLogsExactlyOneModeEnter() {
        let fake = FakeUsage()
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map, usage: fake)
        XCTAssertEqual(fake.types(), ["mode.enter"], "no mode.leave/mode.enter from the init assignment")
        XCTAssertEqual(fake.events[0].data["mode"], .string(vm.mode.rawValue))
        vm.mode = vm.mode == .explore ? .navigation : .explore
        XCTAssertEqual(fake.types(), ["mode.enter", "mode.leave", "mode.enter"], "later changes still logged")
    }

    func testNewSessionContextRelogsMapModeAndPositioning() {
        let fake = FakeUsage()
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map, usage: fake)
        vm.mode = .navigation
        fake.clear()
        vm.logSessionContext()
        XCTAssertEqual(fake.types(), ["map.loaded", "mode.enter"], "no positioning running, none re-logged")
        XCTAssertEqual(fake.events[0].data["ms"], .number(0))
        XCTAssertEqual(fake.events[0].data["name"], .string(SampleGreenhouseMap.map.name))
        XCTAssertEqual(fake.events[0].data["source"], "cache")
        XCTAssertEqual(fake.events[1].data["mode"], "Navigate")

        let version = LocalMapVersion(version: 4, source: .web, updatedAt: Date(), slug: "flower-dome")
        let events = NavigationViewModel.sessionContext(map: SampleGreenhouseMap.map, version: version, mapSource: "network",
                                                        mode: .explore, positioning: ["source": "glasses", "localizer": "cloud"])
        XCTAssertEqual(events.map(\.0), ["map.loaded", "mode.enter", "positioning.start"])
        XCTAssertEqual(events[0].1["slug"], "flower-dome")
        XCTAssertEqual(events[0].1["version"], .number(4))
        XCTAssertEqual(events[0].1["source"], "cache")
        XCTAssertEqual(events[0].1["ms"], .number(0))
        XCTAssertEqual(events[1].1["mode"], "Explore")
        XCTAssertEqual(events[2].1["source"], "glasses")
        let bundled = NavigationViewModel.sessionContext(map: SampleGreenhouseMap.map, version: nil, mapSource: "bundle",
                                                         mode: .navigation, positioning: nil)
        XCTAssertEqual(bundled[0].1["source"], "bundle")
        XCTAssertEqual(bundled[0].1["slug"], .null)
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
        XCTAssertEqual(fake.types(), ["settings.changed", "beacon"])
        XCTAssertEqual(fake.events[0].data["key"], "beep_guidance")
        XCTAssertEqual(fake.events[1].data["on"], .bool(!was))
        vm.beaconEnabled = was
    }

    // MARK: - Task 4: speech, navigation, pose, Explore

    func testPoseSamplerOnePerSecond() {
        var sampler = PoseSampler()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let results = [0, 0.4, 1.0, 1.5, 2.1].map { sampler.shouldSample(at: t0.addingTimeInterval($0)) }
        XCTAssertEqual(results, [true, false, true, false, true])
    }

    func testStartAndStopNavigationLogged() {
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map)
        let fake = FakeUsage()
        vm.usage = fake
        vm.arManager.usage = fake
        vm.arManager.apply(trackingState: .normal)
        vm.selectedDestination = vm.destinations.first { $0.id == "orchid" }
        vm.startNavigation()
        XCTAssertTrue(vm.isNavigating)
        vm.stopNavigation()

        let nav = fake.events.filter { $0.type.hasPrefix("nav.") }
        XCTAssertEqual(nav.map(\.type), ["nav.request", "nav.start", "nav.cancel"])
        XCTAssertEqual(nav[0].data["to_id"], "orchid")
        XCTAssertEqual(nav[0].data["to_name"], "Orchid Display")
        if case .number(let metres)? = nav[0].data["path_m"] { XCTAssertGreaterThan(metres, 10) } else { XCTFail("path_m") }
        XCTAssertEqual(nav[2].data["reason"], "user")
        XCTAssertEqual(nav[2].data["to_id"], "orchid")
        XCTAssertNotNil(nav[2].data["seconds"])
        XCTAssertEqual(nav[2].data["walked_m"], 0)
        XCTAssertEqual(fake.events.first { $0.type == "ar.tracking" }?.data["state"], "normal")
    }

    func testHeardAndIntentLogged() {
        let vm = NavigationViewModel(map: SampleGreenhouseMap.map)
        let fake = FakeUsage()
        vm.usage = fake
        vm.handleWelcome(transcript: "take me to the exit")
        let speech = fake.events.filter { $0.type.hasPrefix("speech.") && $0.type != "speech.said" }
        XCTAssertEqual(speech.map(\.type), ["speech.heard", "speech.intent"])
        XCTAssertEqual(speech[0].data["text"], "take me to the exit")
        XCTAssertEqual(speech[0].data["via"], "phone")
        XCTAssertEqual(speech[1].data["text"], "take me to the exit")
        XCTAssertNotNil(speech[1].data["intent"])
    }

    func testExploreAskLogsFailure() async {
        TestURLStub.reset()
        TestURLStub.stub = (500, "boom")
        defer { TestURLStub.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLStub.self]
        let fake = FakeUsage()
        let client = ExploreClient(session: URLSession(configuration: configuration), usage: fake)
        do {
            for try await _ in client.ask(question: "what is this?", jpeg: nil, mapSlug: "m", places: [],
                                          venueInfo: nil, history: []) {}
            XCTFail("a 500 must throw")
        } catch {}
        XCTAssertEqual(fake.types(), ["explore.ask"])
        let data = fake.events[0].data
        XCTAssertEqual(data["ok"], false)
        XCTAssertEqual(data["had_image"], false)
        XCTAssertEqual(data["question"], "what is this?")
        XCTAssertNotNil(data["error"])
        XCTAssertNotEqual(data["error"], .null)
        XCTAssertNotNil(data["ms"])
    }
}
