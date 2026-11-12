import Foundation
import simd

/// Turns the chain a mapping walk produces into a corridor graph.
///
/// `MapAuthoringSession` links every mark to the one before it, in walking
/// order, so a walk is always one long chain. Real walks double back: the
/// mapper steps into a room and returns, or passes the same corner twice. The
/// chain then has two waypoints for one corner, and long links laid over
/// corridor it has already drawn, so a route to a room at the end of a spur
/// has to go through the room before it. On 12 Nov 2026 the AHLab Level 3
/// walk needed all of this fixing by hand in the editor; these two passes
/// reproduce that hand edit.
///
/// 1. Waypoints closer than `mergeRadius` are one corner: merge them.
/// 2. A link that passes within `snapRadius` of another point runs along
///    ground that point is on: route it through the point instead.
///
/// Pure, and safe to run twice. It never moves or removes a place the mapper
/// marked; only the automatic waypoints (junctions) are merged.
enum RouteTidy {

    struct Report: Equatable {
        var mergedWaypoints = 0
        var reroutedLinks = 0
        var changed: Bool { mergedWaypoints > 0 || reroutedLinks > 0 }
    }

    /// Two passes through one corner land this close (metres); corners of a
    /// real corridor are further apart than a corridor is wide.
    static let mergeRadius: Float = 2.0
    /// Half a corridor: a point this close to a link is standing on it.
    static let snapRadius: Float = 1.0
    /// Points further apart in height than this are on different floors.
    static let floorGap: Float = 1.5

    static func tidy(_ map: NavigationMap) -> (map: NavigationMap, report: Report) {
        var pois = map.pois
        var report = Report()
        // Links as unordered id pairs, in order, without repeats or dangling ends.
        var links: [(String, String)] = []
        func add(_ a: String, _ b: String, to list: inout [(String, String)]) {
            guard a != b, !list.contains(where: { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }) else { return }
            list.append((a, b))
        }
        let known = Set(pois.map(\.id))
        var dangling: [NavigationEdge] = []
        for edge in map.edges {
            if known.contains(edge.from), known.contains(edge.to) { add(edge.from, edge.to, to: &links) } else { dangling.append(edge) }
        }

        // 1. Merge waypoints that are the same corner, closest pair first.
        while true {
            var best: (i: Int, j: Int, d: Float)?
            for i in pois.indices where pois[i].category == .junction {
                for j in pois.indices where j > i && pois[j].category == .junction && sameFloor(pois[i], pois[j]) {
                    let d = simd_distance(pois[i].planarPosition, pois[j].planarPosition)
                    if d < mergeRadius, d < (best?.d ?? .infinity) { best = (i, j, d) }
                }
            }
            guard let (i, j, _) = best else { break }
            let keep = pois[i].id, drop = pois[j].id
            pois[i].x = (pois[i].x + pois[j].x) / 2
            pois[i].z = (pois[i].z + pois[j].z) / 2
            if let a = pois[i].y, let b = pois[j].y { pois[i].y = (a + b) / 2 } else { pois[i].y = pois[i].y ?? pois[j].y }
            pois.remove(at: j)
            var relinked: [(String, String)] = []
            for (a, b) in links { add(a == drop ? keep : a, b == drop ? keep : b, to: &relinked) }
            links = relinked
            report.mergedWaypoints += 1
        }

        // 2. Route each link through any point standing on it. Every split
        // replaces a link with two shorter ones, so this ends.
        var index = 0
        while index < links.count {
            let (a, b) = links[index]
            guard let pa = pois.first(where: { $0.id == a }), let pb = pois.first(where: { $0.id == b }),
                  let via = pointOn(pa, pb, among: pois) else { index += 1; continue }
            links.remove(at: index)
            add(a, via, to: &links)
            add(via, b, to: &links)
            report.reroutedLinks += 1
            index = 0
        }

        guard report.changed else { return (map, report) }
        var tidy = map
        tidy.pois = pois
        tidy.edges = links.map { NavigationEdge(from: $0.0, to: $0.1) } + dangling
        return (tidy, report)
    }

    /// The point nearest the line a–b that stands on it, clear of both ends.
    private static func pointOn(_ a: NavigationPOI, _ b: NavigationPOI, among pois: [NavigationPOI]) -> String? {
        let pa = a.planarPosition, pb = b.planarPosition
        let ab = pb - pa
        let lengthSquared = simd_length_squared(ab)
        guard lengthSquared > 0 else { return nil }
        var best: (id: String, d: Float)?
        for c in pois where c.id != a.id && c.id != b.id && sameFloor(a, c) && sameFloor(b, c) {
            let pc = c.planarPosition
            let t = simd_dot(pc - pa, ab) / lengthSquared
            guard t > 0, t < 1 else { continue }
            let d = simd_distance(pc, pa + t * ab)
            guard d < snapRadius, simd_distance(pc, pa) > snapRadius, simd_distance(pc, pb) > snapRadius else { continue }
            if d < (best?.d ?? .infinity) { best = (c.id, d) }
        }
        return best?.id
    }

    private static func sameFloor(_ a: NavigationPOI, _ b: NavigationPOI) -> Bool {
        guard let ya = a.y, let yb = b.y else { return true }
        return abs(ya - yb) < floorGap
    }
}
