import Foundation
import GameplayKit
import simd

/// What the visitor asked for: how long they have and, optionally, what they like.
struct TourRequest: Equatable {
    var minutes: Double
    var interests: [String] = []
    /// POI ids that go in whatever the budget says.
    var mustSee: [String] = []
}

/// An ordered visit: start → stops → end, with its estimated time.
struct TourPlan: Equatable {
    var startID: String
    var endID: String
    var stopIDs: [String]
    var walkMinutes: Double
    var dwellMinutes: Double
    var totalMinutes: Double { walkMinutes + dwellMinutes }
}

/// Picks and orders the stops of a timed visit. Deterministic and offline: walking
/// time is the A* path length at a stroll, dwell time is each place's `minutes`.
/// The language model never computes the route; at most it fills a `TourRequest`.
struct TourPlanner {
    static let strollSpeed: Double = 0.7       // m/s
    static let budgetFraction: Double = 0.9    // leave 10% for stopping to look around

    let map: NavigationMap
    let startID: String?
    let endID: String?
    let candidates: [NavigationPOI]
    private let engine: PathfindingEngine
    private let legs: LegCache

    init(map: NavigationMap) {
        self.map = map
        let engine = PathfindingEngine(map: map)
        self.engine = engine
        self.legs = LegCache(engine: engine)
        let ids = Set(map.pois.map(\.id))
        let start = map.tourStart.flatMap { ids.contains($0) ? $0 : nil }
            ?? (ids.contains("entrance") ? "entrance" : nil)
            ?? engine.destinations.first?.id
        startID = start
        endID = map.tourEnd.flatMap { ids.contains($0) ? $0 : nil } ?? start
        if let start {
            let end = endID
            let legs = self.legs
            candidates = map.pois.filter { poi in
                poi.category == .exhibit && poi.highlightLevel != 0
                    && poi.id != start && poi.id != end
                    && legs.metres(start, poi.id) != nil
            }
        } else {
            candidates = []
        }
    }

    // MARK: - Planning

    func plan(_ request: TourRequest) -> TourPlan? {
        guard let startID, let endID else { return nil }
        let budget = request.minutes * Self.budgetFraction
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var stops: [String] = []

        for id in request.mustSee where byID[id] != nil && !stops.contains(id) {
            stops.insert(id, at: cheapestInsertion(of: id, into: stops).index)
        }

        while true {
            let current = minutes(of: stops) ?? .infinity
            var best: (id: String, index: Int, score: Double)?
            for poi in candidates where !stops.contains(poi.id) {
                let (index, addedWalk) = cheapestInsertion(of: poi.id, into: stops)
                let added = addedWalk + poi.visitMinutes
                guard added > 0, current + added <= budget else { continue }
                let score = value(of: poi, interests: request.interests) / added
                if best == nil || score > best!.score { best = (poi.id, index, score) }
            }
            guard let best else { break }
            stops.insert(best.id, at: best.index)
        }

        return evaluate(stopIDs: twoOpt(stops), start: startID, end: endID)
    }

    /// Times a given order without changing it; nil when a leg cannot be walked.
    func evaluate(stopIDs: [String]) -> TourPlan? {
        guard let startID, let endID else { return nil }
        return evaluate(stopIDs: stopIDs, start: startID, end: endID)
    }

    func removing(_ id: String, from plan: TourPlan) -> TourPlan {
        let stops = twoOpt(plan.stopIDs.filter { $0 != id })
        return evaluate(stopIDs: stops, start: plan.startID, end: plan.endID) ?? plan
    }

    func adding(_ id: String, to plan: TourPlan) -> TourPlan {
        guard !plan.stopIDs.contains(id), candidates.contains(where: { $0.id == id }) else { return plan }
        var stops = plan.stopIDs
        stops.insert(id, at: cheapestInsertion(of: id, into: stops).index)
        return evaluate(stopIDs: stops, start: plan.startID, end: plan.endID) ?? plan
    }

    /// Planned arrival minute at each stop, then at the end, walking at a stroll
    /// and staying each stop's `visitMinutes`.
    func schedule(_ plan: TourPlan) -> [Double] {
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let route = [plan.startID] + plan.stopIDs + [plan.endID]
        var clock: Double = 0
        var arrivals: [Double] = []
        for (i, (a, b)) in zip(route, route.dropFirst()).enumerated() {
            if i > 0 { clock += byID[a]?.visitMinutes ?? 0 }
            clock += Double(legs.metres(a, b) ?? 0) / Self.strollSpeed / 60
            arrivals.append(clock)
        }
        return arrivals
    }

    // MARK: - Pieces

    /// Must see 3, good 2, if there's time 1; a tag matching an interest adds 2,
    /// so what the visitor asked for beats a highlight they did not.
    private func value(of poi: NavigationPOI, interests: [String]) -> Double {
        var v = Double(max(0, 4 - poi.highlightLevel))
        let wanted = interests.map { $0.lowercased() }.filter { !$0.isEmpty }
        let matches = poi.tags.contains { tag in
            let t = tag.lowercased()
            return wanted.contains { t.contains($0) || $0.contains(t) }
        }
        if matches { v += 2 }
        return v
    }

    private func evaluate(stopIDs: [String], start: String, end: String) -> TourPlan? {
        guard let walk = walkMinutes(start: start, stops: stopIDs, end: end) else { return nil }
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let dwell = stopIDs.reduce(0) { $0 + (byID[$1]?.visitMinutes ?? 0) }
        return TourPlan(startID: start, endID: end, stopIDs: stopIDs, walkMinutes: walk, dwellMinutes: dwell)
    }

    private func minutes(of stops: [String]) -> Double? {
        guard let startID, let endID else { return nil }
        return evaluate(stopIDs: stops, start: startID, end: endID)?.totalMinutes
    }

    private func walkMinutes(start: String, stops: [String], end: String) -> Double? {
        let route = [start] + stops + [end]
        var metres: Float = 0
        for (a, b) in zip(route, route.dropFirst()) {
            guard let leg = legs.metres(a, b) else { return nil }
            metres += leg
        }
        return Double(metres) / Self.strollSpeed / 60
    }

    /// Where `id` adds the least walking, and how many minutes of walking it adds.
    private func cheapestInsertion(of id: String, into stops: [String]) -> (index: Int, addedWalk: Double) {
        guard let startID, let endID else { return (stops.count, .infinity) }
        let base = walkMinutes(start: startID, stops: stops, end: endID) ?? .infinity
        var best = (index: stops.count, addedWalk: Double.infinity)
        for index in 0...stops.count {
            var trial = stops
            trial.insert(id, at: index)
            guard let walk = walkMinutes(start: startID, stops: trial, end: endID) else { continue }
            if walk - base < best.addedWalk { best = (index, walk - base) }
        }
        return best
    }

    /// Reverses stretches of the order while that shortens the walk.
    private func twoOpt(_ stops: [String]) -> [String] {
        guard let startID, let endID, stops.count > 1 else { return stops }
        var order = stops
        var bestWalk = walkMinutes(start: startID, stops: order, end: endID) ?? .infinity
        var improved = true
        while improved {
            improved = false
            for i in 0..<(order.count - 1) {
                for j in (i + 1)..<order.count {
                    var trial = order
                    trial[i...j].reverse()
                    if let walk = walkMinutes(start: startID, stops: trial, end: endID), walk < bestWalk - 1e-9 {
                        order = trial
                        bestWalk = walk
                        improved = true
                    }
                }
            }
        }
        return order
    }
}

/// Shortest walkable distance between two places, memoised: the planner asks
/// for the same pairs many times.
private final class LegCache {
    private let engine: PathfindingEngine
    private var cache: [String: Float?] = [:]

    init(engine: PathfindingEngine) { self.engine = engine }

    func metres(_ a: String, _ b: String) -> Float? {
        if a == b { return 0 }
        let key = a < b ? "\(a)|\(b)" : "\(b)|\(a)"
        if let hit = cache[key] { return hit }
        let path = engine.findPath(from: a, to: b)
        let length: Float? = path.count < 2 ? nil
            : zip(path, path.dropFirst()).reduce(Float(0)) { $0 + simd_distance($1.0.position, $1.1.position) }
        cache[key] = length
        return length
    }
}
