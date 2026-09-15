//
// AiSeeH264Decoder.swift — AiSeeGlassKit
//
// Hardware H.264 → CVPixelBuffer via VideoToolbox. Adapted from the vendor
// demo's CMSampleBufferToPixelBufferAdapter. The session is created lazily
// from the first sample's format description and recreated when VideoToolbox
// reports it unhealthy (which happens after a background excursion).
// No vendor SDK import — compiles everywhere.
//

import CoreMedia
import CoreVideo
import VideoToolbox

final class AiSeeH264Decoder {
    private var session: VTDecompressionSession?
    private static let recreateErrors: Set<OSStatus> = [
        kVTVideoDecoderNotAvailableNowErr,  // -12903
        kVTVideoDecoderMalfunctionErr,      // -12911
        kVTInvalidSessionErr,                        // -12990
        kVTFormatDescriptionChangeNotSupportedErr,   // -12916
    ]

    deinit { invalidate() }

    func decode(_ sample: CMSampleBuffer, onFrame: @escaping (CVPixelBuffer) -> Void) {
        guard let format = sample.formatDescription else { return }
        // A resolution/SPS change mid-stream needs a new session; VideoToolbox
        // otherwise rejects the frame with kVTFormatDescriptionChangeNotSupportedErr.
        if let session, !VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: format) {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        if session == nil { session = Self.makeSession(for: format) }
        guard let session else { return }

        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) {
            status, _, imageBuffer, _, _ in
            if status == noErr, let imageBuffer { onFrame(imageBuffer) }
        }
        if Self.recreateErrors.contains(status) {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }

    func invalidate() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
    }

    private static func makeSession(for format: CMFormatDescription) -> VTDecompressionSession? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil, formatDescription: format, decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &session)
        return status == noErr ? session : nil
    }
}
