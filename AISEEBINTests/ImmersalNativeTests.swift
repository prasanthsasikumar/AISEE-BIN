import XCTest
import simd
@testable import AISEEBIN

/// The native plugin's answer, carried into the same `ImmersalRawPose` the
/// REST client produces so nothing downstream has to know which one ran.
///
/// The simulator links stubs that fail every call, which is exactly what a
/// corrupt or missing map does on a device, so those paths are tested here.
final class ImmersalNativeTests: XCTestCase {

    func testRawPoseFromQuaternionMatchesMatrixBuiltDirectly() {
        let q = simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.1)))
        let raw = ImmersalNative.rawPose(position: SIMD3(1, 2, 3), rotation: q)
        let expected = simd_float3x3(q)
        // `r` is row-major: r[row * 3 + col]; simd's `m[col][row]` is column col, row row.
        for row in 0..<3 {
            for col in 0..<3 {
                XCTAssertEqual(raw.r[row * 3 + col], expected[col][row], accuracy: 1e-5, "row \(row) col \(col)")
            }
        }
        XCTAssertEqual(raw.px, 1)
        XCTAssertEqual(raw.py, 2)
        XCTAssertEqual(raw.pz, 3)
        XCTAssertTrue(raw.isWellFormed)
        // The existing decoder reads it under the confirmed convention.
        let pose = ImmersalPose.cameraPoseInMap(raw)
        XCTAssertNotNil(pose)
        XCTAssertEqual(pose!.columns.3.x, 1)
    }

    func testIdentityRotationIsIdentityMatrix() {
        let raw = ImmersalNative.rawPose(position: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        XCTAssertEqual(raw.r, [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    func testStubLoadFailsAndNothingStaysLoaded() {
        let native = ImmersalNative()
        XCTAssertFalse(native.load(mapID: 151670, data: Data(repeating: 0, count: 64)))
        XCTAssertEqual(native.loadedMapIDs, [])
    }

    func testStubLocalizeReportsNoMatchWithoutCrashing() {
        let native = ImmersalNative()
        let frame = GrayFrame(pixels: Data(count: 4), width: 2, height: 2)
        let result = native.localize(frame, intrinsics: (1, 1, 1, 1))
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "no match")
        XCTAssertNil(result.mapID)
        XCTAssertNil(result.pose)
        XCTAssertEqual(result.requestBytes, 4)
    }

    func testNativeLocalizerIsNamedOnDevice() async {
        let localizer = NativeImmersalLocalizer(native: ImmersalNative())
        XCTAssertEqual(localizer.name, "on device")
        let result = await localizer.localize(GrayFrame(pixels: Data(count: 1), width: 1, height: 1),
                                              intrinsics: (1, 1, 0, 0))
        XCTAssertEqual(result.error, "no match")
    }

    func testCloudLocalizerIsNamedCloudAndReportsTransportFailure() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLStub.self]
        TestURLStub.stub = nil   // no stub: the request fails as if offline
        let localizer = CloudImmersalLocalizer(token: "t", mapIDs: [1], session: URLSession(configuration: configuration))
        XCTAssertEqual(localizer.name, "cloud")
        let result = await localizer.localize(GrayFrame(pixels: Data(count: 4), width: 2, height: 2),
                                              intrinsics: (1, 1, 1, 1))
        XCTAssertFalse(result.success)
        XCTAssertTrue(ImmersalClient.isTransportFailure(result.error), result.error)
    }
}
