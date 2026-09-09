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
/// The path's first node is the user's start node, so the first *target* is
/// index 1. Value semantics keep this trivially testable.
struct RouteTracker {

    let path: [GKGraphNode2D]
    private let thresholds: GuidanceThresholds
    private(set) var targetIndex: Int

    init(path: [GKGraphNode2D], thresholds: GuidanceThresholds) {
        self.path = path
        self.thresholds = thresholds
        // A path of 0 or 1 nodes means there is nowhere to go.
        targetIndex = path.count > 1 ? 1 : path.count
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
        guard !hasArrived else { return nil }
        for node in path[targetIndex...] {
            guard let poi = (node as? POIGraphNode)?.poi else { continue }
            if poi.category != .junction { return poi.name }
        }
        return (path.last as? POIGraphNode)?.poi.name
    }

    /// Advances the target when the user is within the arrival radius.
    mutating func update(position: SIMD2<Float>) -> RouteEvent {
        guard let target = targetNode else { return .none }
        guard simd_distance(position, target.position) <= thresholds.arrivalDistance else { return .none }

        let id = (target as? POIGraphNode)?.poi.id ?? "?"
        targetIndex += 1
        return hasArrived ? .arrived(id) : .reachedNode(id)
    }

    /// `true` when the user is further than `offRouteDistance` from the leg they
    /// should be walking along.
    func isOffRoute(position: SIMD2<Float>) -> Bool {
        guard let target = targetNode else { return false }
        let from = previousNode?.position ?? target.position
        return NavigationGeometry.distance(from: position, toSegment: from, target.position) > thresholds.offRouteDistance
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
}
