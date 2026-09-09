import XCTest
@testable import AISEEBIN

final class GzipCodecTests: XCTestCase {

    /// Compressible, but not trivially so — like a world map archive.
    private func sampleData(count: Int) -> Data {
        var data = Data(capacity: count)
        var seed: UInt64 = 0x2545F491
        for i in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            // Long runs with occasional noise: gzip should get a real win here.
            data.append(i % 64 < 48 ? UInt8(i % 7) : UInt8(truncatingIfNeeded: seed >> 33))
        }
        return data
    }

    func testRoundTripsArbitraryBytes() throws {
        for count in [0, 1, 2, 17, 1024, 65_535, 65_536, 300_000] {
            let original = sampleData(count: count)
            let restored = try GzipCodec.decompress(GzipCodec.compress(original))
            XCTAssertEqual(restored, original, "round trip failed at \(count) bytes")
        }
    }

    func testCompressesRepetitiveDataSubstantially() {
        let original = Data(repeating: 0x41, count: 200_000)
        let compressed = GzipCodec.compress(original)
        XCTAssertLessThan(compressed.count, original.count / 10,
                          "highly repetitive data should compress by well over 10x")
    }

    func testEmitsAGzipHeaderAndTrailer() {
        let original = Data("greenhouse".utf8)
        let compressed = GzipCodec.compress(original)

        XCTAssertEqual(Array(compressed.prefix(3)), [0x1f, 0x8b, 0x08], "gzip magic and DEFLATE method")
        // Trailer is CRC32 then ISIZE, both little-endian.
        let isize = compressed.suffix(4)
        XCTAssertEqual(Array(isize), [UInt8(original.count), 0, 0, 0])
        let crc = compressed.dropLast(4).suffix(4)
        let expected = GzipCodec.crc32(original)
        XCTAssertEqual(Array(crc), [UInt8(expected & 0xFF), UInt8((expected >> 8) & 0xFF),
                                    UInt8((expected >> 16) & 0xFF), UInt8((expected >> 24) & 0xFF)])
    }

    /// CRC-32 of "123456789" is the standard IEEE check value.
    func testCRC32MatchesTheStandardCheckValue() {
        XCTAssertEqual(GzipCodec.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    /// Produced by GNU gzip: `printf 'hello aisee\n' | gzip -9 | base64`.
    /// Proves the decoder reads real gzip, not merely its own output.
    func testDecodesAStreamProducedByGNUGzip() throws {
        let base64 = "H4sIAAAAAAACA8tIzcnJV0jMLE5N5QIAoEKxWwwAAAA="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(try GzipCodec.decompress(data), Data("hello aisee\n".utf8))
    }

    func testDecodesAStreamCarryingAFilenameHeader() throws {
        // Same payload, written by `gzip -9 -N` so FNAME is set in the flags.
        let base64 = "H4sICEr2oGoCA3dvcmxkAMtIzcnJV0jMLE5N5QIAoEKxWwwAAAA="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(try GzipCodec.decompress(data), Data("hello aisee\n".utf8))
    }

    func testRejectsDataThatIsNotGzip() {
        XCTAssertThrowsError(try GzipCodec.decompress(Data(repeating: 0x00, count: 64))) { error in
            XCTAssertEqual(error as? GzipCodec.Failure, .notGzip)
        }
    }

    func testRejectsATruncatedStream() {
        XCTAssertThrowsError(try GzipCodec.decompress(Data([0x1f, 0x8b, 0x08]))) { error in
            XCTAssertEqual(error as? GzipCodec.Failure, .truncated)
        }
    }

    func testRejectsAStreamWhoseChecksumDoesNotMatch() {
        var compressed = GzipCodec.compress(Data("greenhouse".utf8))
        compressed[compressed.count - 5] ^= 0xFF      // corrupt the stored CRC
        XCTAssertThrowsError(try GzipCodec.decompress(compressed)) { error in
            XCTAssertEqual(error as? GzipCodec.Failure, .corrupt)
        }
    }

    func testRecognisesCompressedStoragePaths() {
        XCTAssertTrue(GzipCodec.isCompressed(path: "home/v3/greenhouse.arworldmap.gz"))
        XCTAssertFalse(GzipCodec.isCompressed(path: "default/v2/greenhouse.arworldmap"))
    }

    /// Writes a gzip stream to a path the build can check with `gunzip -t`,
    /// so encoder interoperability is verified against the real tool, not just
    /// against this file's own decoder.
    func testWritesAStreamForExternalGunzipVerification() throws {
        let payload = sampleData(count: 500_000)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisee-gzip-interop.gz")
        try GzipCodec.compress(payload).write(to: url)
        try payload.write(to: url.deletingPathExtension().appendingPathExtension("raw"))
        print("[gzip-interop] wrote \(url.path)")
    }
}

extension GzipCodec.Failure: Equatable {}
