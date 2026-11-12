import XCTest
@testable import AISEEBIN

final class GlassesKindTests: XCTestCase {

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testKindDefaultsToAiSeeAndRoundTrips() {
        let defaults = freshDefaults()
        XCTAssertEqual(GlassesKind.load(from: defaults), .aisee)
        GlassesKind.rayban.save(to: defaults)
        XCTAssertEqual(GlassesKind.load(from: defaults), .rayban)
        defaults.set("monocle", forKey: GlassesKind.key)
        XCTAssertEqual(GlassesKind.load(from: defaults), .aisee)
    }

    func testAiSeeLandscapeIntrinsicsAreWhatTheyAlwaysWere() {
        let k = GlassesCamera(focalPx: 1100).intrinsics(width: 1280, height: 720)
        XCTAssertEqual(k.fx, 1100); XCTAssertEqual(k.fy, 1100)
        XCTAssertEqual(k.ox, 640); XCTAssertEqual(k.oy, 360)
        let half = GlassesCamera(focalPx: 1100).intrinsics(width: 640, height: 360)
        XCTAssertEqual(half.fx, 550)
    }

    func testPortraitFramesScaleByTheirLongEdge() {
        let k = GlassesCamera(focalPx: 1100).intrinsics(width: 720, height: 1280)
        XCTAssertEqual(k.fx, 1100); XCTAssertEqual(k.fy, 1100)
        XCTAssertEqual(k.ox, 360); XCTAssertEqual(k.oy, 640)
        XCTAssertEqual(GlassesCamera(focalPx: 1100).intrinsics(width: 360, height: 640).fx, 550)
    }

    func testEachKindKeepsItsOwnFocalLength() {
        let defaults = freshDefaults()
        GlassesCamera(focalPx: 1100).save(kind: .aisee, to: defaults)
        GlassesCamera(focalPx: 700).save(kind: .rayban, to: defaults)
        XCTAssertEqual(GlassesCamera.load(kind: .aisee, from: defaults).focalPx, 1100)
        XCTAssertEqual(GlassesCamera.load(kind: .rayban, from: defaults).focalPx, 700)
        XCTAssertEqual(defaults.float(forKey: "glasses.camera.focalPx"), 1100)
    }

    func testPlainLoadAndSaveFollowTheChosenKind() {
        let defaults = freshDefaults()
        GlassesCamera(focalPx: 1100).save(to: defaults)          // AiSee by default
        GlassesKind.rayban.save(to: defaults)
        XCTAssertEqual(GlassesCamera.load(from: defaults).focalPx, GlassesCamera.defaultFocalPx)
        GlassesCamera(focalPx: 750).save(to: defaults)
        XCTAssertEqual(GlassesCamera.load(from: defaults).focalPx, 750)
        GlassesKind.aisee.save(to: defaults)
        XCTAssertEqual(GlassesCamera.load(from: defaults).focalPx, 1100)
    }
}
