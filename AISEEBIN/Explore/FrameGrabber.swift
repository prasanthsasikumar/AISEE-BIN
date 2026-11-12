import ARKit
import CoreImage
import UIKit

/// Turns the camera frame ARKit is already capturing into a small upright JPEG
/// for a question; no second camera session. A glasses frame goes through the
/// same shrink, already upright.
enum FrameGrabber {
    private static let context = CIContext()

    static func jpeg(from frame: ARFrame, longEdge: CGFloat = 768, quality: CGFloat = 0.6) -> Data? {
        // The sensor is landscape; the phone is held upright.
        jpeg(from: CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right), longEdge: longEdge, quality: quality)
    }

    /// A frame from the glasses' stream, which arrives the right way up.
    static func jpeg(from pixelBuffer: CVPixelBuffer, longEdge: CGFloat = 768, quality: CGFloat = 0.6) -> Data? {
        jpeg(from: CIImage(cvPixelBuffer: pixelBuffer), longEdge: longEdge, quality: quality)
    }

    private static func jpeg(from source: CIImage, longEdge: CGFloat, quality: CGFloat) -> Data? {
        var image = source
        let scale = longEdge / max(image.extent.width, image.extent.height)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.jpegRepresentation(of: image, colorSpace: colorSpace,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }
}
