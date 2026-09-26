import UIKit
import XCTest
@testable import AISEEBIN

/// The tightly packed 8-bit frames the native plugin consumes, and the PNG
/// the cloud path still needs. The row-padding case is the one that matters:
/// ARKit's luma plane is often wider in bytes than in pixels, and feeding the
/// padded bytes to a pose solver yields plausible-looking nonsense.
final class ImmersalFrameEncoderTests: XCTestCase {

    func testPackedLumaDropsRowPaddingAndHalves() {
        // 4x2 image whose rows are padded to 8 bytes; a pixel's value is 10 × its column.
        var bytes = Data(count: 16)
        for row in 0..<2 { for col in 0..<4 { bytes[row * 8 + col] = UInt8(col * 10) } }
        let plane = ImmersalFrameEncoder.LumaPlane(bytes: bytes, width: 4, height: 2, rowBytes: 8)

        let full = ImmersalFrameEncoder.packedLuma(from: plane, factor: 1)!
        XCTAssertEqual(full.width, 4)
        XCTAssertEqual(full.height, 2)
        XCTAssertEqual(Array(full.pixels), [0, 10, 20, 30, 0, 10, 20, 30])

        let half = ImmersalFrameEncoder.packedLuma(from: plane, factor: 2)!
        XCTAssertEqual(half.width, 2)
        XCTAssertEqual(half.height, 1)
        XCTAssertEqual(half.pixels.count, 2)
    }

    func testGrayFromBGRAHasWidthTimesHeightBytes() {
        let image = ImmersalFrameEncoder.BGRAImage(bytes: Data(repeating: 200, count: 8 * 4 * 4),
                                                   width: 8, height: 4, rowBytes: 32)
        let gray = ImmersalFrameEncoder.gray(from: image, targetWidth: 4)!
        XCTAssertEqual(gray.width, 4)
        XCTAssertEqual(gray.height, 2)
        XCTAssertEqual(gray.pixels.count, 8)
        XCTAssertEqual(gray.pixels.first, 200, "a flat 200 gray image stays 200 after scaling")
    }

    func testPNGFromGrayFrameDecodesToSameSize() {
        let frame = GrayFrame(pixels: Data(repeating: 7, count: 6), width: 3, height: 2)
        let png = ImmersalFrameEncoder.png(from: frame)!
        XCTAssertEqual(UIImage(data: png)?.size, CGSize(width: 3, height: 2))
    }
}
