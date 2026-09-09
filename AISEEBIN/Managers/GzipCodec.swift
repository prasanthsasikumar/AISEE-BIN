import Foundation
import Compression

/// A minimal gzip (RFC 1952) container around the system's raw DEFLATE codec.
///
/// Map blobs are stored gzipped: the 31.7 MB world map compresses to 23.1 MB
/// (72.7%, measured on the real archive — ARWorldMap is already dense), which is
/// most of a minute saved on a link that manages 155 KB/s. gzip rather
/// than a bare DEFLATE stream because the same objects are read by the web
/// editor's `DecompressionStream('gzip')` and downloaded by hand from the version
/// list, where a file `gunzip` understands is worth the eighteen-byte overhead.
enum GzipCodec {

    enum Failure: LocalizedError {
        case notGzip
        case truncated
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notGzip:   return "Data is not in gzip format."
            case .truncated: return "Compressed data ended early."
            case .corrupt:   return "Compressed data failed its checksum."
            }
        }
    }

    /// `true` when a storage path names a gzipped object.
    static func isCompressed(path: String) -> Bool { path.hasSuffix(".gz") }

    // MARK: Compress

    static func compress(_ input: Data) -> Data {
        // Magic, CM = deflate, no flags, no mtime, no extra flags, OS = unknown.
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(deflate(input))
        out.append(littleEndian(crc32(input)))
        out.append(littleEndian(UInt32(truncatingIfNeeded: input.count)))
        return out
    }

    private static func deflate(_ input: Data) -> Data {
        // The empty DEFLATE stream: one final stored block of length zero.
        guard !input.isEmpty else { return Data([0x03, 0x00]) }

        // Incompressible input grows slightly; stored blocks cost 5 bytes per 64 KB.
        let capacity = input.count + input.count / 16 + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_encode_buffer(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), capacity,
                                          src.baseAddress!.assumingMemoryBound(to: UInt8.self), input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        // 0 means the codec declined; a stored-block copy is still a valid stream.
        guard written > 0 else { return storedBlocks(input) }
        return out.prefix(written)
    }

    /// DEFLATE stored (uncompressed) blocks — the fallback when the codec declines.
    private static func storedBlocks(_ input: Data) -> Data {
        var out = Data()
        var offset = 0
        while offset < input.count {
            let length = min(0xFFFF, input.count - offset)
            let isFinal: UInt8 = (offset + length == input.count) ? 1 : 0
            out.append(isFinal)
            out.append(littleEndian(UInt16(length)))
            out.append(littleEndian(UInt16(~UInt16(length))))
            out.append(input[input.startIndex + offset ..< input.startIndex + offset + length])
            offset += length
        }
        return out
    }

    // MARK: Decompress

    static func decompress(_ input: Data) throws -> Data {
        // Re-base so a slice from the network can be indexed from zero.
        let data = input.startIndex == 0 ? input : Data(input)
        guard data.count >= 18 else { throw Failure.truncated }
        guard data[0] == 0x1f, data[1] == 0x8b else { throw Failure.notGzip }
        guard data[2] == 0x08 else { throw Failure.notGzip }

        let flags = data[3]
        var cursor = 10
        if flags & 0x04 != 0 {                                  // FEXTRA
            guard cursor + 2 <= data.count else { throw Failure.truncated }
            cursor += 2 + Int(data[cursor]) | Int(data[cursor + 1]) << 8
        }
        if flags & 0x08 != 0 { cursor = try skipCString(data, from: cursor) }   // FNAME
        if flags & 0x10 != 0 { cursor = try skipCString(data, from: cursor) }   // FCOMMENT
        if flags & 0x02 != 0 { cursor += 2 }                                    // FHCRC

        let footer = data.count - 8
        guard cursor <= footer else { throw Failure.truncated }

        let expectedCRC = readLE32(data, at: footer)
        let expectedSize = Int(readLE32(data, at: footer + 4))
        let output = inflate(data[cursor..<footer], expecting: expectedSize)

        guard output.count == expectedSize else { throw Failure.truncated }
        guard crc32(output) == expectedCRC else { throw Failure.corrupt }
        return output
    }

    private static func inflate(_ input: Data, expecting size: Int) -> Data {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_decode_buffer(dst.baseAddress!.assumingMemoryBound(to: UInt8.self), size,
                                          src.baseAddress!.assumingMemoryBound(to: UInt8.self), input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return out.prefix(written)
    }

    private static func skipCString(_ data: Data, from start: Int) throws -> Int {
        var cursor = start
        while cursor < data.count && data[cursor] != 0 { cursor += 1 }
        guard cursor < data.count else { throw Failure.truncated }
        return cursor + 1
    }

    // MARK: Bytes

    private static func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    /// CRC-32 (IEEE 802.3), the checksum gzip stores in its trailer.
    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { acc, _ in
            acc & 1 == 1 ? 0xEDB88320 ^ (acc >> 1) : acc >> 1
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        let table = crcTable
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
