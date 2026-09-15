#if DEBUG
import CoreVideo
import Foundation
import UIKit
import simd

// THROWAWAY — see ImmersalPose.swift.

/// Turns an ARKit camera buffer into the image `/localizeb64` wants, and scales
/// the camera intrinsics to match.
///
/// `/localizeb64` accepts "8-bit grayscale or 24-bit RGB" PNG. ARKit hands us
/// `kCVPixelFormatType_420YpCbCr8BiPlanar…`, whose **first plane is already
/// 8-bit luma** — so the grayscale path is a plane copy rather than a colour
/// conversion, and it is what a feature matcher would reduce the image to anyway.
///
/// The buffer is used in its native sensor orientation (landscape-right),
/// because that is the orientation `ARCamera.intrinsics` describes and the
/// orientation `ARCamera.transform` is expressed in. Rotating the image without
/// rotating the intrinsics is the classic way to get plausible-looking nonsense
/// out of a VPS, so neither is touched.
enum ProbeFrameEncoder {

    /// Full sensor frames are ~1920×1440; halving cuts the base64 payload to
    /// roughly a quarter, which matters on greenhouse Wi-Fi. Immersal maps built
    /// by the Mapper app localize comfortably at this scale.
    static let downscale = 2

    /// A copy of the luma plane, detached from ARKit's buffer pool.
    ///
    /// Copied rather than retained: holding a `CVPixelBuffer` holds a slot in
    /// ARKit's pool, and starving that pool degrades the very tracking we are
    /// trying to measure. The copy is a straight `memcpy` on the main actor
    /// (sub-millisecond); PNG encoding then happens off it.
    struct LumaPlane: Sendable {
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

        guard factor > 1 else { return UIImage(cgImage: source).pngData() }

        let w = plane.width / factor, h = plane.height / factor
        guard let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}
#endif
