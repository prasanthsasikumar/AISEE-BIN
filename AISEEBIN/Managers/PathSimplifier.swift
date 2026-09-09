import Foundation
import simd

/// Ramer–Douglas–Peucker line simplification on the floor plane. Used to turn a
/// walked breadcrumb trail into the few corner waypoints that describe a corridor.
enum PathSimplifier {

    /// Keeps the endpoints and any point that deviates more than `tolerance`
    /// metres from the straight line between its neighbours' kept points.
    static func simplify(_ points: [SIMD2<Float>], tolerance: Float) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplify(points, from: 0, to: points.count - 1, tolerance: tolerance, keep: &keep)
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func simplify(_ points: [SIMD2<Float>], from start: Int, to end: Int,
                                 tolerance: Float, keep: inout [Bool]) {
        guard end - start > 1 else { return }
        var farthest = start
        var maxDistance: Float = 0
        for i in (start + 1)..<end {
            let d = NavigationGeometry.distance(from: points[i], toSegment: points[start], points[end])
            if d > maxDistance {
                maxDistance = d
                farthest = i
            }
        }
        guard maxDistance > tolerance else { return }
        keep[farthest] = true
        simplify(points, from: start, to: farthest, tolerance: tolerance, keep: &keep)
        simplify(points, from: farthest, to: end, tolerance: tolerance, keep: &keep)
    }
}
