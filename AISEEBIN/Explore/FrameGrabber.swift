import ARKit
import CoreImage
import UIKit

/// Turns the camera frame ARKit is already capturing into a small upright JPEG
/// for a question; no second camera session. The glasses can supply frames
/// through the same `jpeg` shape later.
enum FrameGrabber {
    private static let context = CIContext()

    static func jpeg(from frame: ARFrame, longEdge: CGFloat = 768, quality: CGFloat = 0.6) -> Data? {
        // The sensor is landscape; the phone is held upright.
        var image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = longEdge / max(image.extent.width, image.extent.height)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.jpegRepresentation(of: image, colorSpace: colorSpace,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }
}
