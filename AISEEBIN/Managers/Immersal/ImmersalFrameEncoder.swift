import CoreVideo
import Foundation
import UIKit
import simd

/// Turns a camera buffer into the image `/localizeb64` wants, and scales the
/// camera intrinsics to match.
///
/// `/localizeb64` accepts "8-bit grayscale or 24-bit RGB" PNG. Two sources feed
/// it:
///
/// - **ARKit** hands us `kCVPixelFormatType_420YpCbCr8BiPlanar…`, whose first
///   plane is already 8-bit luma, so the grayscale path is a plane copy.
/// - **The glasses** stream decodes to 32BGRA, which CoreGraphics reduces to
///   gray on the way into the PNG.
///
/// Either way the pixels are *copied* out of the source buffer on the delivery
/// thread — holding a `CVPixelBuffer` holds a slot in the producer's pool — and
/// the PNG is encoded from the copy, off that thread.
///
/// The buffer is used in its native sensor orientation, because that is the
/// orientation the intrinsics describe and the camera transform is expressed
/// in. Rotating the image without rotating the intrinsics is the classic way to
/// get plausible-looking nonsense out of a VPS, so neither is touched.
enum ImmersalFrameEncoder {

    /// Phone frames are ~1920×1440; halving cuts the base64 payload to roughly a
    /// quarter, which matters on greenhouse Wi-Fi. Immersal maps built by the
    /// Mapper app localize comfortably at this scale. The glasses stream is
    /// already 1280×720 and is sent at full size.
    static let downscale = 2

    /// A copy of one 8-bit plane, detached from the source's buffer pool.
    struct LumaPlane: Sendable {
        var bytes: Data
        var width: Int
        var height: Int
        var rowBytes: Int
    }

    /// A copy of a 32BGRA image, likewise detached.
    struct BGRAImage: Sendable {
        var bytes: Data
        var width: Int
        var height: Int
        var rowBytes: Int
    }

    static func copyLuma(from buffer: CVPixelBuffer) -> LumaPlane? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        return LumaPlane(bytes: Data(bytes: base, count: rowBytes * height),
                         width: width, height: height, rowBytes: rowBytes)
    }

    static func copyBGRA(from buffer: CVPixelBuffer) -> BGRAImage? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        return BGRAImage(bytes: Data(bytes: base, count: rowBytes * height),
                         width: width, height: height, rowBytes: rowBytes)
    }

    /// Camera intrinsics for an image reduced by `factor`.
    ///
    /// All four terms are in pixels and scale linearly with resolution — the
    /// one step that is easy to forget and that silently ruins every pose.
    static func scaledIntrinsics(_ k: simd_float3x3, factor: Int = downscale)
        -> (fx: Float, fy: Float, ox: Float, oy: Float) {
        let s = 1 / Float(factor)
        return (fx: k.columns.0.x * s, fy: k.columns.1.y * s,
                ox: k.columns.2.x * s, oy: k.columns.2.y * s)
    }

    /// 8-bit grayscale PNG of `plane`, reduced by `factor`.
    static func grayscalePNG(from plane: LumaPlane, factor: Int = downscale) -> Data? {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: plane.bytes as CFData),
              let source = CGImage(width: plane.width, height: plane.height,
                                   bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: plane.rowBytes, space: gray,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                   provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return grayscalePNG(drawing: source, width: plane.width, height: plane.height, factor: factor)
    }

    /// 8-bit grayscale PNG of a BGRA image, reduced by `factor` (1 = full size).
    static func grayscalePNG(from image: BGRAImage, factor: Int = 1) -> Data? {
        let rgb = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let provider = CGDataProvider(data: image.bytes as CFData),
              let source = CGImage(width: image.width, height: image.height,
                                   bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: image.rowBytes, space: rgb,
                                   bitmapInfo: info,
                                   provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return grayscalePNG(drawing: source, width: image.width, height: image.height, factor: factor)
    }

    /// 8-bit grayscale PNG of a BGRA image scaled to `targetWidth` pixels wide,
    /// aspect kept, with the size the PNG actually has (intrinsics must be
    /// computed for *that* size). Halving 1280×720 to 960×540 roughly halves
    /// the payload, which is most of a fix's latency over cellular.
    static func grayscalePNG(from image: BGRAImage, targetWidth: Int) -> (png: Data, width: Int, height: Int)? {
        guard let source = cgImage(from: image) else { return nil }
        let w = min(max(1, targetWidth), image.width)
        let h = max(1, image.height * w / image.width)
        guard let png = grayscalePNG(drawing: source, targetWidth: w, targetHeight: h,
                                     interpolate: w < image.width) else { return nil }
        return (png, w, h)
    }

    private static func cgImage(from image: BGRAImage) -> CGImage? {
        let rgb = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.premultipliedFirst.rawValue)
        guard let provider = CGDataProvider(data: image.bytes as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.rowBytes, space: rgb,
                       bitmapInfo: info,
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draws `source` into a gray context of the reduced size and encodes it.
    /// Drawing into a gray context is also what converts colour to luma.
    private static func grayscalePNG(drawing source: CGImage, width: Int, height: Int, factor: Int) -> Data? {
        grayscalePNG(drawing: source, targetWidth: width / max(1, factor), targetHeight: height / max(1, factor),
                     interpolate: factor > 1)
    }

    private static func grayscalePNG(drawing source: CGImage, targetWidth w: Int, targetHeight h: Int,
                                     interpolate: Bool) -> Data? {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = interpolate ? .high : .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}
