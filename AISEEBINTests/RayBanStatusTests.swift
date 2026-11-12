import XCTest
@testable import AISEEBIN

final class RayBanStatusTests: XCTestCase {

    // MARK: - Status

    private var ready: RayBanInputs {
        RayBanInputs(metaAppMissing: false, registration: .registered, cameraGranted: true,
                     deviceName: "Prasanth's Ray-Ban", linked: true, sessionPaused: false)
    }

    func testEachMissingStepIsReportedInOrder() {
        var i = RayBanInputs()
        XCTAssertEqual(RayBanStatus.resolve(i), .needsRegistration)
        i.registration = .available
        XCTAssertEqual(RayBanStatus.resolve(i), .needsRegistration)
        i.registration = .registering
        XCTAssertEqual(RayBanStatus.resolve(i), .registering)
        i.registration = .registered
        XCTAssertEqual(RayBanStatus.resolve(i), .needsCameraPermission)
        i.cameraGranted = true
        XCTAssertEqual(RayBanStatus.resolve(i), .noDevice)
        i.linked = true
        XCTAssertEqual(RayBanStatus.resolve(i), .ready(name: "Ray-Ban Meta"))
        i.deviceName = "Prasanth's Ray-Ban"
        XCTAssertEqual(RayBanStatus.resolve(i), .ready(name: "Prasanth's Ray-Ban"))
        i.sessionPaused = true
        XCTAssertEqual(RayBanStatus.resolve(i), .paused(name: "Prasanth's Ray-Ban"))
    }

    func testMissingMetaAppBeatsEverything() {
        var i = ready
        i.metaAppMissing = true
        XCTAssertEqual(RayBanStatus.resolve(i), .metaAppMissing)
    }

    func testConnectedMeansReadyOrPaused() {
        XCTAssertTrue(RayBanStatus.ready(name: "x").isConnected)
        XCTAssertTrue(RayBanStatus.paused(name: "x").isConnected)
        for status in [RayBanStatus.metaAppMissing, .needsRegistration, .registering, .needsCameraPermission, .noDevice] {
            XCTAssertFalse(status.isConnected, "\(status)")
        }
    }

    // MARK: - Losing the glasses

    /// Feeds the policy once a second and collects what it asked for.
    private func run(_ policy: inout GlassesLossPolicy, from: Int, through: Int,
                     linked: Bool, frames: Bool) -> [GlassesLossPolicy.Event] {
        (from...through).flatMap { policy.update(linked: linked, framesFlowing: frames, now: TimeInterval($0)) }
    }

    func testLinkLostForTenSecondsFallsBackOnce() {
        var policy = GlassesLossPolicy()
        XCTAssertEqual(run(&policy, from: 0, through: 9, linked: false, frames: false), [])
        XCTAssertEqual(run(&policy, from: 10, through: 10, linked: false, frames: false), [.fallBackToPhone])
        XCTAssertEqual(run(&policy, from: 11, through: 120, linked: false, frames: false), [])
    }

    func testAShortDropIsRiddenOutSilently() {
        var policy = GlassesLossPolicy()
        XCTAssertEqual(run(&policy, from: 0, through: 5, linked: false, frames: false), [])
        XCTAssertEqual(run(&policy, from: 6, through: 60, linked: true, frames: true), [])
        // A second short drop starts its own clock.
        XCTAssertEqual(run(&policy, from: 61, through: 69, linked: false, frames: false), [])
    }

    func testGlassesTakenOffNeverFallBackToThePhone() {
        var policy = GlassesLossPolicy()
        XCTAssertEqual(run(&policy, from: 0, through: 3, linked: true, frames: true), [])
        XCTAssertEqual(run(&policy, from: 4, through: 13, linked: true, frames: false), [])
        XCTAssertEqual(run(&policy, from: 14, through: 14, linked: true, frames: false), [.announcePaused])
        XCTAssertEqual(run(&policy, from: 15, through: 300, linked: true, frames: false), [])
    }

    func testFramesReturningAfterAnAnnouncedPauseAreAnnounced() {
        var policy = GlassesLossPolicy()
        _ = run(&policy, from: 0, through: 0, linked: true, frames: true)
        _ = run(&policy, from: 1, through: 11, linked: true, frames: false)
        XCTAssertEqual(run(&policy, from: 12, through: 12, linked: true, frames: true), [.announceBack])
        XCTAssertEqual(run(&policy, from: 13, through: 20, linked: true, frames: true), [])
    }

    func testFramesReturningBeforeTheGraceSayNothing() {
        var policy = GlassesLossPolicy()
        _ = run(&policy, from: 0, through: 0, linked: true, frames: true)
        XCTAssertEqual(run(&policy, from: 1, through: 9, linked: true, frames: false), [])
        XCTAssertEqual(run(&policy, from: 10, through: 30, linked: true, frames: true), [])
    }

    func testACameraThatHasNotStartedYetIsNotAnnouncedAsPaused() {
        var policy = GlassesLossPolicy()
        XCTAssertEqual(run(&policy, from: 0, through: 60, linked: true, frames: false), [])
        XCTAssertEqual(run(&policy, from: 61, through: 70, linked: true, frames: true), [])
        // Once it has run, a real pause is announced.
        XCTAssertEqual(run(&policy, from: 71, through: 81, linked: true, frames: false), [.announcePaused])
    }

    func testAPauseThatTurnsIntoALostLinkStillFallsBack() {
        var policy = GlassesLossPolicy()
        _ = run(&policy, from: 0, through: 0, linked: true, frames: true)
        _ = run(&policy, from: 1, through: 10, linked: true, frames: false)
        XCTAssertEqual(run(&policy, from: 11, through: 20, linked: false, frames: false), [])
        XCTAssertEqual(run(&policy, from: 21, through: 21, linked: false, frames: false), [.fallBackToPhone])
    }
}
