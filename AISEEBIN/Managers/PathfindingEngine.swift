import Foundation
import GameplayKit
import simd

/// A graph node that remembers which POI it represents so that path results can
/// be turned back into names for speech and UI.
final class POIGraphNode: GKGraphNode2D {
    let poi: NavigationPOI

    init(poi: NavigationPOI) {
        self.poi = poi
        super.init(point: poi.planarPosition)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("POIGraphNode does not support NSCoding") }
}

/// Distance and heading from the user to a target node, recomputed every frame.
struct GuidanceVector: Equatable {
    /// Metres along the floor plane.
    let distance: Float
    /// Radians in (-π, π]; positive = turn right.
    let relativeAngle: Float
}

/// Builds a `GKGraph` from a `NavigationMap` and answers routing and
/// "where is the next node relative to me" questions.
///
/// `GKGraphNode2D` already implements the A* cost and heuristic as Euclidean
/// distance, so `GKGraph.findPath` gives us A* for free.
final class PathfindingEngine {

    let map: NavigationMap
    private let graph = GKGraph()
    private let nodesByID: [String: POIGraphNode]

    init(map: NavigationMap) {
        self.map = map

        var lookup: [String: POIGraphNode] = [:]
        for poi in map.pois {
            lookup[poi.id] = POIGraphNode(poi: poi)
        }
        nodesByID = lookup
        graph.add(Array(lookup.values))

        for edge in map.edges {
            guard let a = lookup[edge.from], let b = lookup[edge.to] else {
                assertionFailure("Edge references unknown node: \(edge)")
                continue
            }
            a.addConnections(to: [b], bidirectional: true)
        }
    }

    // MARK: - Lookup

    /// Nodes the user may pick as a destination (junctions are excluded).
    var destinations: [NavigationPOI] {
        map.pois.filter(\.isDestination).sorted { $0.name < $1.name }
    }

    func node(named id: String) -> GKGraphNode2D? { nodesByID[id] }

    /// Identifier of a node returned from `findPath`.
    func name(of node: GKGraphNode2D) -> String {
        (node as? POIGraphNode)?.poi.id ?? "?"
    }

    /// Human-readable display name for a node.
    func displayName(of node: GKGraphNode2D) -> String {
        (node as? POIGraphNode)?.poi.name ?? "unknown"
    }

    /// The graph node closest to a floor-plane position. Used to choose the
    /// route start once the user has relocalized.
    func nearestNode(to position: SIMD2<Float>) -> GKGraphNode2D? {
        nodesByID.values.min { simd_distance_squared($0.position, position) < simd_distance_squared($1.position, position) }
    }

    // MARK: - Routing

    /// A* shortest path between two node identifiers. Returns an empty array when
    /// either node is unknown or no route exists.
    func findPath(from startNode: String, to targetNode: String) -> [GKGraphNode2D] {
        guard let start = nodesByID[startNode], let target = nodesByID[targetNode] else { return [] }
        return graph.findPath(from: start, to: target).compactMap { $0 as? GKGraphNode2D }
    }

    // MARK: - Live guidance

    /// Distance and turn angle from the camera pose to a node.
    func guidanceVector(from cameraTransform: simd_float4x4, to node: GKGraphNode2D) -> GuidanceVector {
        let position = NavigationGeometry.planarPosition(of: cameraTransform)
        let heading = NavigationGeometry.heading(of: cameraTransform)
        return GuidanceVector(
            distance: NavigationGeometry.distance(from: position, to: node.position),
            relativeAngle: NavigationGeometry.relativeBearing(from: position, heading: heading, to: node.position)
        )
    }
}

// MARK: - "What's around me"

struct NearbyPOI: Equatable {
    let poi: NavigationPOI
    let distance: Float
    let side: RelativeSide
}

extension PathfindingEngine {
    /// Navigable or announceable POIs within `maxDistance`, nearest first.
    /// Junctions are excluded because they mean nothing to the user.
    func nearby(position: SIMD2<Float>, heading: Float, maxDistance: Float, limit: Int) -> [NearbyPOI] {
        map.pois
            .filter { $0.category != .junction }
            .map { poi -> NearbyPOI in
                let angle = NavigationGeometry.relativeBearing(from: position, heading: heading, to: poi.planarPosition)
                return NearbyPOI(poi: poi,
                                 distance: simd_distance(position, poi.planarPosition),
                                 side: RelativeSide(relativeAngle: angle))
            }
            .filter { $0.distance <= maxDistance && $0.distance > 0.01 }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }
}
