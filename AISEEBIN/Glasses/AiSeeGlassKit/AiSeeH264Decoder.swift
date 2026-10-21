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

    func decode(_ sample: CMSampleBuffer, onFrame: @escaping (CVPixelBuffer, CMTime) -> Void) {
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
            status, _, imageBuffer, presentationTime, _ in
            if status == noErr, let imageBuffer { onFrame(imageBuffer, presentationTime) }
        }
        if Self.recreateErrors.contains(status) {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }

    /// Whether `sample` (AVCC: 4-byte big-endian length before each NAL unit)
    /// holds an IDR slice, NAL type 5.
    static func containsIDR(_ sample: CMSampleBuffer) -> Bool {
        guard let block = sample.dataBuffer else { return false }
        let length = CMBlockBufferGetDataLength(block)
        var offset = 0
        while offset + 5 <= length {
            var header = [UInt8](repeating: 0, count: 5)
            guard CMBlockBufferCopyDataBytes(block, atOffset: offset, dataLength: 5, destination: &header) == noErr
            else { return false }
            let nalLength = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[4] & 0x1F == 5 { return true }
            guard nalLength > 0 else { return false }
            offset += 4 + nalLength
        }
        return false
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
