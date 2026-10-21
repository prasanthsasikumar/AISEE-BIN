import CoreMedia
import XCTest
@testable import AISEEBIN

/// Frame selection for glasses fixes: the sharpness score, the keyframe and
/// sharpness filters with their starvation guard, and IDR detection.
final class GlassesFrameSelectorTests: XCTestCase {

    // MARK: - FrameSharpness

    func testFlatFrameScoresZero() {
        let frame = GrayFrame(pixels: Data(repeating: 128, count: 64 * 48), width: 64, height: 48)
        XCTAssertEqual(FrameSharpness.score(frame), 0, accuracy: 0.001)
    }

    func testNoiseScoresAboveThresholdAndGentleRampBelow() {
        let w = 96, h = 64
        var sharp = Data(count: w * h)
        var soft = Data(count: w * h)
        var seed: UInt32 = 12345
        for y in 0..<h {
            for x in 0..<w {
                seed = seed &* 1_103_515_245 &+ 12345      // fixed LCG: same noise every run
                sharp[y * w + x] = UInt8(truncatingIfNeeded: seed >> 16)
                soft[y * w + x] = UInt8(120 + (x % 8))   // a gentle ramp
            }
        }
        let sharpScore = FrameSharpness.score(GrayFrame(pixels: sharp, width: w, height: h))
        let softScore = FrameSharpness.score(GrayFrame(pixels: soft, width: w, height: h))
        XCTAssertGreaterThan(sharpScore, GlassesFrameSelector.minSharpness)
        XCTAssertLessThan(softScore, GlassesFrameSelector.minSharpness)
    }

    // MARK: - GlassesFrameSelector

    func testAllFilterAdmitsEverything() {
        let selector = GlassesFrameSelector()
        selector.reset(filter: .all, now: 0)
        XCTAssertTrue(selector.admits(isKeyframe: false, now: 0.1))
        XCTAssertTrue(selector.admits(sharpness: 1, now: 0.1))
    }

    func testSharpFilterSkipsBlurryUntilMaxWait() {
        let selector = GlassesFrameSelector()
        selector.reset(filter: .sharp, now: 0)
        XCTAssertFalse(selector.admits(sharpness: 10, now: 0.5))
        XCTAssertTrue(selector.admits(sharpness: 200, now: 0.6))
        XCTAssertFalse(selector.admits(sharpness: 10, now: 1.0))
        // Nothing sent for maxWait: the next frame goes however blurry.
        XCTAssertTrue(selector.admits(sharpness: 10, now: 0.6 + GlassesFrameSelector.maxWait))
        XCTAssertEqual(selector.skippedBlurry, 2)
    }

    func testKeyframeFilterSkipsPFramesUntilMaxWait() {
        let selector = GlassesFrameSelector()
        selector.reset(filter: .keyframes, now: 0)
        XCTAssertFalse(selector.admits(isKeyframe: false, now: 0.5))
        XCTAssertTrue(selector.admits(isKeyframe: true, now: 0.6))
        XCTAssertTrue(selector.admits(isKeyframe: false, now: GlassesFrameSelector.maxWait + 0.1))
        XCTAssertEqual(selector.skippedNonKey, 1)
    }

    func testFilterCanChangeMidSession() {
        let selector = GlassesFrameSelector()
        selector.reset(filter: .sharp, now: 0)
        selector.set(filter: .all)
        XCTAssertTrue(selector.admits(sharpness: 1, now: 0.1))
    }

    // MARK: - IDR detection

    func testIDRDetectedInAVCCSample() throws {
        // SEI (type 6) then an IDR slice (type 5), each with a 4-byte length.
        let bytes: [UInt8] = [0, 0, 0, 2, 0x06, 0xAA, 0, 0, 0, 3, 0x65, 0x88, 0x84]
        XCTAssertTrue(AiSeeH264Decoder.containsIDR(try sample(bytes)))
    }

    func testPFrameIsNotIDR() throws {
        let bytes: [UInt8] = [0, 0, 0, 3, 0x41, 0x9A, 0x02]
        XCTAssertFalse(AiSeeH264Decoder.containsIDR(try sample(bytes)))
    }

    private func sample(_ bytes: [UInt8]) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                          blockLength: bytes.count, blockAllocator: kCFAllocatorDefault,
                                                          customBlockSource: nil, offsetToData: 0, dataLength: bytes.count,
                                                          flags: 0, blockBufferOut: &block), noErr)
        let buffer = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: bytes, blockBuffer: buffer, offsetIntoDestination: 0,
                                                     dataLength: bytes.count), noErr)
        var out: CMSampleBuffer?
        var size = bytes.count
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: buffer, formatDescription: nil,
                                                 sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                                 sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &out), noErr)
        return try XCTUnwrap(out)
    }
}
