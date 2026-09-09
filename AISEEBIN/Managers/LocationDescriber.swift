import Foundation
import simd

/// Where the user is, expressed only in terms of named places. Waypoints
/// (junctions) shape the route but are never spoken: a blind user cannot do
/// anything with "next to Waypoint 3".
enum LocationDescription: Equatable {
    /// Within `LocationDescriber.atRadius` of a named place.
    case at(NavigationPOI)
    /// On a corridor: the nearer and farther named places reached by walking
    /// the graph in each direction, with the walking distance and the side of
    /// the nearer one.
    case between(nearer: NavigationPOI, farther: NavigationPOI, distanceToNearer: Float, side: RelativeSide)
    /// Off the graph: straight-line to the nearest named place.
    case near(NavigationPOI, distance: Float, side: RelativeSide)

    var spokenText: String {
        switch self {
        case .at(let poi):
            return "You are at the \(poi.name)."
        case .between(let nearer, let farther, let distance, let side):
            return "You are between the \(nearer.name) and the \(farther.name), about \(Self.metres(distance)) from the \(nearer.name), \(side.phrase)."
        case .near(let poi, let distance, let side):
            return "You are about \(Self.metres(distance)) from the \(poi.name), \(side.phrase)."
        }
    }

    /// The same fact trimmed for the screen: no "You are" preamble and "m" rather
    /// than "meters". Used by the off-route "Last known" panel.
    var screenText: String {
        switch self {
        case .at(let poi):
            return "at the \(poi.name)"
        case .between(let nearer, let farther, let distance, let side):
            return "between the \(nearer.name) and the \(farther.name), about \(Self.shortMetres(distance)) from the \(nearer.name), \(side.phrase)"
        case .near(let poi, let distance, let side):
            return "about \(Self.shortMetres(distance)) from the \(poi.name), \(side.phrase)"
        }
    }

    private static func shortMetres(_ value: Float) -> String {
        "\(max(1, Int(value.rounded()))) m"
    }

    private static func metres(_ value: Float) -> String {
        let n = max(1, Int(value.rounded()))
        return n == 1 ? "1 meter" : "\(n) meters"
    }
}

struct LocationDescriber {

    /// "You are at" radius, metres.
    static let atRadius: Float = 2.0
    /// Beyond this distance from every edge the user is treated as off the graph.
    static let onEdgeRadius: Float = 4.0

    private let pois: [String: NavigationPOI]
    private let edges: [NavigationEdge]
    private let neighbours: [String: [String]]

    init(map: NavigationMap) {
        let lookup = Dictionary(uniqueKeysWithValues: map.pois.map { ($0.id, $0) })
        let validEdges = map.edges.filter { lookup[$0.from] != nil && lookup[$0.to] != nil }
        pois = lookup
        edges = validEdges
        var adjacency: [String: [String]] = [:]
        for edge in validEdges {
            adjacency[edge.from, default: []].append(edge.to)
            adjacency[edge.to, default: []].append(edge.from)
        }
        neighbours = adjacency
    }

    func describe(position: SIMD2<Float>, heading: Float) -> LocationDescription? {
        let named = pois.values.filter { $0.category != .junction }
        guard let nearestNamed = named.min(by: { simd_distance($0.planarPosition, position) < simd_distance($1.planarPosition, position) }) else {
            return nil
        }
        let straightLine = simd_distance(nearestNamed.planarPosition, position)
        if straightLine <= Self.atRadius {
            return .at(nearestNamed)
        }

        // Find the corridor the user is standing in.
        let nearestEdge = edges.min { edgeDistance($0, to: position) < edgeDistance($1, to: position) }
        if let edge = nearestEdge, edgeDistance(edge, to: position) <= Self.onEdgeRadius,
           let from = pois[edge.from], let to = pois[edge.to] {
            let towardFrom = nearestNamedPlace(from: from.id, excluding: to.id, startDistance: simd_distance(position, from.planarPosition))
            let towardTo = nearestNamedPlace(from: to.id, excluding: from.id, startDistance: simd_distance(position, to.planarPosition))

            let candidates = [(towardFrom, from), (towardTo, to)].compactMap { result, endpoint in
                result.map { (place: $0.place, distance: $0.distance, endpoint: endpoint) }
            }.sorted { $0.distance < $1.distance }

            if let nearer = candidates.first {
                let side = RelativeSide(relativeAngle: NavigationGeometry.relativeBearing(from: position, heading: heading, to: nearer.endpoint.planarPosition))
                if let farther = candidates.dropFirst().first(where: { $0.place.id != nearer.place.id }) {
                    return .between(nearer: nearer.place, farther: farther.place, distanceToNearer: nearer.distance, side: side)
                }
                return .near(nearer.place, distance: nearer.distance, side: side)
            }
        }

        let side = RelativeSide(relativeAngle: NavigationGeometry.relativeBearing(from: position, heading: heading, to: nearestNamed.planarPosition))
        return .near(nearestNamed, distance: straightLine, side: side)
    }

    // MARK: - Private

    private func edgeDistance(_ edge: NavigationEdge, to position: SIMD2<Float>) -> Float {
        guard let a = pois[edge.from], let b = pois[edge.to] else { return .greatestFiniteMagnitude }
        return NavigationGeometry.distance(from: position, toSegment: a.planarPosition, b.planarPosition)
    }

    /// Dijkstra from `start` (which may itself be named) to the closest named
    /// place, never passing through `excluded`, so the search only looks away
    /// from the user's current corridor.
    private func nearestNamedPlace(from start: String, excluding excluded: String, startDistance: Float) -> (place: NavigationPOI, distance: Float)? {
        var best: [String: Float] = [start: startDistance]
        var frontier: [(id: String, distance: Float)] = [(start, startDistance)]
        var visited: Set<String> = [excluded]

        while !frontier.isEmpty {
            frontier.sort { $0.distance < $1.distance }
            let current = frontier.removeFirst()
            guard !visited.contains(current.id), let node = pois[current.id] else { continue }
            visited.insert(current.id)
            if node.category != .junction {
                return (node, current.distance)
            }
            for next in neighbours[current.id] ?? [] where !visited.contains(next) {
                guard let nextPOI = pois[next] else { continue }
                let d = current.distance + simd_distance(node.planarPosition, nextPOI.planarPosition)
                if d < best[next] ?? .greatestFiniteMagnitude {
                    best[next] = d
                    frontier.append((next, d))
                }
            }
        }
        return nil
    }
}
