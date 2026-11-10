import Foundation

/// How a route crosses between levels.
enum LevelChangeKind: String, Equatable {
    case stairs, lift
}

/// The floors of a building, worked out from the heights at which places were
/// marked (`NavigationPOI.y`). A map without heights is one level, so every
/// answer here degrades to "same floor" and old maps behave exactly as before.
///
/// Waypoints the Author walk adds along the trail carry no height of their own;
/// they take the height of the nearest node (by hops) that has one.
struct BuildingLevels: Equatable {
    /// Two marked heights further apart than this are on different levels. A
    /// storey is ~3–4 m; hand-held camera height varies well under 1 m.
    static let levelGap: Float = 2.0
    /// Typical camera height above the floor when a place is marked.
    static let cameraHeight: Float = 1.35

    /// Height (camera, metres) per POI id, filled for waypoints; empty when the
    /// map has no heights at all.
    let heights: [String: Float]
    /// Mean camera height of each level, lowest first.
    let levelHeights: [Float]
    private let namesByID: [String: String]

    init(map: NavigationMap) {
        namesByID = Dictionary(map.pois.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var known: [String: Float] = [:]
        for poi in map.pois { if let y = poi.y { known[poi.id] = y } }
        guard !known.isEmpty else { heights = [:]; levelHeights = []; return }

        // Breadth-first from every node with a height: a waypoint takes its nearest one.
        var adjacency: [String: [String]] = [:]
        for edge in map.edges {
            adjacency[edge.from, default: []].append(edge.to)
            adjacency[edge.to, default: []].append(edge.from)
        }
        var filled = known
        var frontier = map.pois.map(\.id).filter { known[$0] != nil }
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                for other in adjacency[id] ?? [] where filled[other] == nil {
                    filled[other] = filled[id]
                    next.append(other)
                }
            }
            frontier = next
        }
        heights = filled
        levelHeights = Self.cluster(Array(known.values))
    }

    /// Groups sorted heights wherever consecutive values jump by more than `levelGap`.
    static func cluster(_ values: [Float]) -> [Float] {
        let sorted = values.sorted()
        guard var group = sorted.first.map({ [$0] }) else { return [] }
        var means: [Float] = []
        for v in sorted.dropFirst() {
            if v - group.last! > levelGap {
                means.append(group.reduce(0, +) / Float(group.count))
                group = [v]
            } else {
                group.append(v)
            }
        }
        means.append(group.reduce(0, +) / Float(group.count))
        return means
    }

    var isMultiLevel: Bool { levelHeights.count > 1 }

    /// 1-based level for a camera height: the nearest level's mean.
    func level(forHeight y: Float) -> Int {
        guard !levelHeights.isEmpty else { return 1 }
        var best = 0
        for (i, h) in levelHeights.enumerated() where abs(h - y) < abs(levelHeights[best] - y) { best = i }
        return best + 1
    }

    /// 1-based level of a place; 1 when the map has no heights.
    func level(of poiID: String) -> Int {
        heights[poiID].map(level(forHeight:)) ?? 1
    }

    /// "Level 2", or nil for a single-level map (no point labelling it).
    func levelName(of poiID: String) -> String? {
        isMultiLevel ? "Level \(level(of: poiID))" : nil
    }

    /// Floor height (metres, world frame) under a place, for drawing on the floor.
    func floorHeight(of poiID: String) -> Float? {
        heights[poiID].map { $0 - Self.cameraHeight }
    }

    /// Whether walking from `a` to `b` changes level, and how. A lift is named as
    /// one ("Lift", "Elevator") at either end; anything else is stairs.
    func levelChange(from a: String, to b: String) -> LevelChangeKind? {
        guard level(of: a) != level(of: b) else { return nil }
        let names = [namesByID[a], namesByID[b]].compactMap { $0?.lowercased() }
        return names.contains { $0.contains("lift") || $0.contains("elevator") } ? .lift : .stairs
    }

    /// "Take the stairs up to Level 2."
    func levelChangeText(from a: String, to b: String) -> String? {
        guard let kind = levelChange(from: a, to: b) else { return nil }
        let up = level(of: b) > level(of: a) ? "up" : "down"
        return "Take the \(kind.rawValue) \(up) to Level \(level(of: b))"
    }
}
