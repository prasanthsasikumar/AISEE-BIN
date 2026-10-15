import XCTest
@testable import AISEEBIN

/// Which way the glasses are used once they connect. The default must stay
/// "phone in a pocket": nobody who never picks Lanyard sees a change.
final class GlassesModeTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "GlassesModeTests")
        defaults.removePersistentDomain(forName: "GlassesModeTests")
    }

    func testDefaultIsPocket() {
        XCTAssertEqual(GlassesMode.load(from: defaults), .pocket)
    }

    func testRoundTripsLanyard() {
        GlassesMode.lanyard.save(to: defaults)
        XCTAssertEqual(GlassesMode.load(from: defaults), .lanyard)
    }

    func testGarbageFallsBackToPocket() {
        defaults.set("hat", forKey: GlassesMode.key)
        XCTAssertEqual(GlassesMode.load(from: defaults), .pocket)
    }

    func testPocketMapsToGlassesSource() {
        XCTAssertEqual(GlassesMode.pocket.source, .glasses)
        XCTAssertEqual(GlassesMode.lanyard.source, .lanyard)
    }

    func testSourceRoundTrip() {
        XCTAssertEqual(GlassesMode(source: .glasses), .pocket)
        XCTAssertEqual(GlassesMode(source: .lanyard), .lanyard)
        XCTAssertNil(GlassesMode(source: .phone))
    }
}
