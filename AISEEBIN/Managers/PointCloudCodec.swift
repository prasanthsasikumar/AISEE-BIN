import Foundation
import simd

/// Compact interchange format for `ARWorldMap.rawFeaturePoints`: consecutive
/// little-endian Float32 `x y z` triples, no header. The web editor reads it
/// straight into a `Float32Array`.
enum PointCloudCodec {

    static func encode(_ points: [SIMD3<Float>]) -> Data {
        var data = Data(capacity: points.count * 12)
        for p in points {
            for value in [p.x, p.y, p.z] {
                var le = value.bitPattern.littleEndian
                withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    static func decode(_ data: Data) -> [SIMD3<Float>] {
        let count = data.count / 12
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let base = i * 12
                let x = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base, as: UInt32.self)))
                let y = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self)))
                let z = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)))
                points.append(SIMD3(x, y, z))
            }
        }
        return points
    }
}
