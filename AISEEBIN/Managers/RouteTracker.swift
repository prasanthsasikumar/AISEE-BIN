import Foundation
import GameplayKit
import simd

/// Discrete progress events emitted while following a route.
enum RouteEvent: Equatable {
    case none
    /// The user arrived at an intermediate node (identifier).
    case reachedNode(String)
    /// The user arrived at the destination (identifier).
    case arrived(String)
}

/// Walks a path produced by `PathfindingEngine` and decides when the user has
/// reached the next node, has arrived, or has strayed from the current leg.
///
/// The path's first node is the node nearest the user, so the first *target* is
/// index 1. A one-node path (the nearest node *is* the destination) still has
/// to be walked to, so its only node is the target. Value semantics keep this
/// trivially testable.
struct RouteTracker {

    let path: [GKGraphNode2D]
    private let thresholds: GuidanceThresholds
    private(set) var targetIndex: Int
    /// Camera height per node id (`BuildingLevels.heights`); empty on maps without heights.
    private let heights: [String: Float]
    /// A node counts as reached only within this height of it, so standing under
    /// the top of the stairs (or in the lift before it moves) is not arriving there.
    static let reachHeightTolerance: Float = 1.5
    /// Where the user stood when the route was planned, and the leg that was
    /// the target then. They rarely stand on the graph, so on that first leg
    /// the straight line from here to the target is as much "the route" as
    /// the graph edge is.
    private let origin: SIMD2<Float>?
    private let firstTargetIndex: Int

    init(path: [GKGraphNode2D], thresholds: GuidanceThresholds, heights: [String: Float] = [:],
         origin: SIMD2<Float>? = nil) {
        self.path = path
        self.thresholds = thresholds
        self.heights = heights
        self.origin = origin
        // An empty path has nowhere to go; a single node is still a place to reach.
        targetIndex = path.count > 1 ? 1 : 0
        firstTargetIndex = targetIndex
    }

    var hasArrived: Bool { targetIndex >= path.count }

    /// The node the user is currently walking toward, or `nil` once arrived.
    var targetNode: GKGraphNode2D? { hasArrived ? nil : path[targetIndex] }

    /// The node the user is walking *from* on the current leg.
    private var previousNode: GKGraphNode2D? {
        guard targetIndex > 0, targetIndex - 1 < path.count else { return nil }
        return path[targetIndex - 1]
    }

    var isFinalLeg: Bool { targetIndex == path.count - 1 }

    /// Name to speak for the current target: waypoints are skipped in favour of
    /// the next named place along the route, so prompts say "toward the Window"
    /// rather than "toward Waypoint 3".
    var spokenTargetName: String? {
        guard let index = spokenTargetIndex else { return nil }
        return (path[index] as? POIGraphNode)?.poi.name
    }

    /// Index of the node `spokenTargetName` names: the next named place from
    /// the current target on, else the destination. `nil` once arrived.
    private var spokenTargetIndex: Int? {
        guard !hasArrived else { return nil }
        for index in targetIndex..<path.count {
            guard let poi = (path[index] as? POIGraphNode)?.poi else { continue }
            if poi.category != .junction { return index }
        }
        return path.count - 1
    }

    /// Metres to walk along the route to the place `spokenTargetName` names,
    /// so a prompt that names a place can give the distance to *that* place
    /// rather than to an unnamed waypoint on the way. 0 once arrived.
    func distanceToSpokenTarget(from position: SIMD2<Float>) -> Float {
        guard let target = targetNode, let end = spokenTargetIndex else { return 0 }
        var total = simd_distance(position, target.position)
        for i in targetIndex..<end {
            total += simd_distance(path[i].position, path[i + 1].position)
        }
        return total
    }

    /// Advances the target when the user is within the arrival radius.
    mutating func update(position: SIMD2<Float>, height: Float? = nil) -> RouteEvent {
        guard let target = targetNode else { return .none }
        guard simd_distance(position, target.position) <= thresholds.arrivalDistance else { return .none }

        let id = (target as? POIGraphNode)?.poi.id ?? "?"
        if let height, let targetHeight = heights[id], abs(height - targetHeight) > Self.reachHeightTolerance {
            return .none
        }
        targetIndex += 1
        return hasArrived ? .arrived(id) : .reachedNode(id)
    }

    /// `true` when the user is further than `offRouteDistance` from the leg they
    /// should be walking along.
    func isOffRoute(position: SIMD2<Float>) -> Bool {
        guard let distance = distanceFromLeg(position: position) else { return false }
        return distance > thresholds.offRouteDistance
    }

    /// Metres from the current leg, or `nil` once arrived.
    func distanceFromLeg(position: SIMD2<Float>) -> Float? {
        guard let target = targetNode else { return nil }
        let from = previousNode?.position ?? target.position
        let fromLeg = NavigationGeometry.distance(from: position, toSegment: from, target.position)
        guard targetIndex == firstTargetIndex, let origin else { return fromLeg }
        return min(fromLeg, NavigationGeometry.distance(from: position, toSegment: origin, target.position))
    }

    /// Metres to walk: current leg remainder plus all following edges.
    func remainingDistance(from position: SIMD2<Float>) -> Float {
        guard let target = targetNode else { return 0 }
        var total = simd_distance(position, target.position)
        for i in targetIndex..<(path.count - 1) {
            total += simd_distance(path[i].position, path[i + 1].position)
        }
        return total
    }

    /// A point `lookAhead` metres further along the route than the user's
    /// projection onto the current leg, or the destination when the route
    /// ends sooner. A beacon aimed here steers along the path instead of
    /// swinging toward each node as it is passed. `nil` once arrived.
    func aimPoint(from position: SIMD2<Float>, lookAhead: Float) -> SIMD2<Float>? {
        guard let target = targetNode else { return nil }
        let from = previousNode?.position ?? target.position
        let leg = target.position - from
        let lengthSquared = simd_length_squared(leg)
        let t: Float = lengthSquared > .ulpOfOne ? simd_clamp(simd_dot(position - from, leg) / lengthSquared, 0, 1) : 1
        var point = from + leg * t
        var remaining = lookAhead
        var index = targetIndex
        var next = target.position
        while true {
            let step = simd_distance(point, next)
            if step >= remaining {
                guard step > .ulpOfOne else { return next }
                return point + (next - point) * (remaining / step)
            }
            remaining -= step
            point = next
            index += 1
            guard index < path.count else { return next }   // ran out of route: the destination
            next = path[index].position
        }
    }
}
