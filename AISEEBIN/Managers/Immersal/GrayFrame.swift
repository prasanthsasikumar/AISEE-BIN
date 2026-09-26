import Foundation

/// One 8-bit grayscale camera frame, tightly packed: `pixels.count ==
/// width * height`, no row padding. What every Immersal localizer consumes,
/// whether it hands the bytes to the native plugin or encodes them to PNG
/// for the cloud.
struct GrayFrame: Sendable, Equatable {
    var pixels: Data
    var width: Int
    var height: Int
}

/// Pinhole intrinsics in pixels for the frame they accompany.
typealias CameraIntrinsics = (fx: Float, fy: Float, ox: Float, oy: Float)
