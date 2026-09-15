//
// AiSeePCMAdapter.swift — AiSeeGlassKit
//
// Packs Int16 mono PCM bytes into AVAudioPCMBuffers (what SFSpeechRecognizer
// consumes) and measures peak level for a meter. The pure helpers are in
// `AiSeePCM` (AVFoundation only, swiftc-testable); the SDK-facing
// AudioStreamInputable sink is below, gated on the SDK.
//

import AVFoundation
import Foundation

enum AiSeePCM {
    static let sampleRate = 16_000.0

    static func makeBuffer(int16 bytes: UnsafeRawPointer, byteCount: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // A frame is one sample *per channel*: for an interleaved stereo format,
        // N Int16s are N/2 frames. Counting samples as frames overstated
        // frameLength by the channel count and read past the buffer.
        let samples = byteCount / MemoryLayout<Int16>.size
        let channels = Int(max(1, format.channelCount))
        let frames = samples / channels
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let dst = buffer.int16ChannelData?[0] else { return nil }
        dst.update(from: bytes.assumingMemoryBound(to: Int16.self), count: frames * channels)
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    static func peakLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return 0 }
        // `abs(Int16)` traps on Int16.min (its magnitude, 32768, has no Int16
        // representation) — widen to Int32 first so the min sample doesn't crash the meter.
        var peak: Int32 = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(Int32(data[i]))) }
        return Float(peak) / 32768.0
    }
}

#if canImport(RTKAudioStreaming)
import RTKAudioStreaming

/// Terminal stream target: receives resampled Int16 PCM from the SDK and emits
/// AVAudioPCMBuffers. Runs on the SDK's audio thread.
final class AiSeePCMSink: AudioStreamInputable {
    let inDataFormat: AudioStreamBasicDescription
    private let format: AVAudioFormat
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    /// Fails rather than traps when the upstream description has no usable
    /// sample rate / channel count (AVAudioFormat returns nil for those).
    init?(upstreamFormat: AudioStreamBasicDescription, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: upstreamFormat.mSampleRate,
                                         channels: AVAudioChannelCount(max(1, upstreamFormat.mChannelsPerFrame)),
                                         interleaved: true) else { return nil }
        self.inDataFormat = upstreamFormat
        self.format = format
        self.onBuffer = onBuffer
    }

    func onAudioStreamFlowStart() {}
    func onAudioStreamFlowEnd() {}

    func receiveAudio(bytes bufferPtr: UnsafeRawPointer, size: UInt, packetNum: UInt,
                      packetDescriptions descs: UnsafePointer<AudioStreamPacketDescription>?) {
        if let buffer = AiSeePCM.makeBuffer(int16: bufferPtr, byteCount: Int(size), format: format) {
            onBuffer(buffer)
        }
    }
}
#endif
