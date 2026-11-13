import Foundation
import simd

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
    /// Places whose height was measured, not inherited from a neighbour.
    private let measured: Set<String>
    private let planar: [String: SIMD2<Float>]

    /// A rise of more than this over a short enough run is a step, not a floor.
    static let stepRise: Float = 0.25
    static let stepSlope: Float = 0.15

    /// Whether going from one measured height to another this far apart climbs like stairs.
    static func isSteep(rise: Float, run: Float) -> Bool {
        abs(rise) > stepRise && abs(rise) > stepSlope * run
    }

    init(map: NavigationMap) {
        namesByID = Dictionary(map.pois.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var known: [String: Float] = [:]
        for poi in map.pois { if let y = poi.y { known[poi.id] = y } }
        measured = Set(known.keys)
        planar = Dictionary(map.pois.map { ($0.id, $0.planarPosition) }, uniquingKeysWith: { a, _ in a })
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
        // A map made from a recorded walk has a height on every node, the
        // steps of a staircase and the length of a ramp included. Those
        // in-between heights would join the floors into one, so the floors are
        // found from the level ground: every measured place that is not at
        // either end of an edge that rises.
        var rising = Set<String>()
        for edge in map.edges {
            guard let a = known[edge.from], let b = known[edge.to], let pa = planar[edge.from], let pb = planar[edge.to] else { continue }
            // Steeper than 4% and more than the wobble of a hand-held height.
            let rise = abs(b - a)
            if rise > 0.15, rise > 0.04 * simd_distance(pa, pb) { rising.insert(edge.from); rising.insert(edge.to) }
        }
        let level = known.filter { !rising.contains($0.key) }
        levelHeights = Self.cluster(Array((level.isEmpty ? known : level).values))
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
    /// Walking up a ramp between two measured heights is not a level change:
    /// there is nothing to climb or ride, and the floor arrives gradually.
    func levelChange(from a: String, to b: String) -> LevelChangeKind? {
        guard level(of: a) != level(of: b) else { return nil }
        if measured.contains(a), measured.contains(b), let ya = heights[a], let yb = heights[b], let pa = planar[a], let pb = planar[b],
           !Self.isSteep(rise: yb - ya, run: simd_distance(pa, pb)) {
            return nil
        }
        let names = [namesByID[a], namesByID[b]].compactMap { $0?.lowercased() }
        return names.contains { $0.contains("lift") || $0.contains("elevator") } ? .lift : .stairs
    }

    /// "Take the stairs up to Level 2."
    func levelChangeText(from a: String, to b: String) -> String? {
        guard let kind = levelChange(from: a, to: b) else { return nil }
        let up = level(of: b) > level(of: a) ? "up" : "down"
        return "Take the \(kind.rawValue) \(up) to Level \(level(of: b))"
    }

    /// The next stairs or lift on `path`: the first one whose far end is at or
    /// after `target`, the index of the node the visitor is heading to.
    ///
    /// A level changes on one edge, which on a real staircase falls somewhere
    /// in the middle. The edges either side that also climb belong to the same
    /// staircase, so `start` is its first step and `end` its last. Where the
    /// heights were measured the climb itself says so; where they were
    /// inherited, nodes named as stairs ("MPH stairs 3") do.
    func stairRun(on path: [String], heading target: Int) -> StairRun? {
        guard path.count > 1 else { return nil }
        func isStair(_ i: Int) -> Bool { namesByID[path[i]]?.lowercased().contains("stair") ?? false }
        /// Whether the edge from node `i` to the next is part of a staircase.
        func climbs(_ i: Int) -> Bool {
            let a = path[i], b = path[i + 1]
            if measured.contains(a), measured.contains(b), let ya = heights[a], let yb = heights[b], let pa = planar[a], let pb = planar[b] {
                return Self.isSteep(rise: yb - ya, run: simd_distance(pa, pb))
            }
            return isStair(i) && isStair(i + 1)
        }
        for i in 0..<(path.count - 1) {
            guard let kind = levelChange(from: path[i], to: path[i + 1]) else { continue }
            var start = i, end = i + 1
            if kind == .stairs {
                while start > 0, climbs(start - 1) { start -= 1 }
                while end < path.count - 1, climbs(end) { end += 1 }
            }
            guard end >= target else { continue }
            let to = level(of: path[i + 1])
            return StairRun(start: start, end: end, kind: kind, up: to > level(of: path[i]), toLevel: to)
        }
        return nil
    }
}

/// One staircase or lift ride on a route (indices into the route's nodes).
struct StairRun: Equatable {
    /// The last node before the first step (or the lift door).
    var start: Int
    /// The first node after the last step.
    var end: Int
    var kind: LevelChangeKind
    var up: Bool
    var toLevel: Int
}
