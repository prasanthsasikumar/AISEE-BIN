import Foundation
import simd

/// Pure editing model behind the authoring screen. Owns a `NavigationMap` and
/// applies the mapper's actions; anchor creation in ARKit is done by the caller.
///
/// Nodes marked one after another are chained by an edge, which mirrors the
/// mapper walking the corridor. Loops are closed with `connect`.
struct MapAuthoringSession {

    private(set) var map: NavigationMap
    /// The node the next `addNode` will be linked from.
    private(set) var lastAddedID: String?

    init(mapName: String) {
        map = NavigationMap(name: mapName, pois: [], edges: [])
    }

    init(map: NavigationMap) {
        self.map = map
        lastAddedID = map.pois.last?.id
    }

    /// Corners closer than this to the straight line are dropped (metres).
    static let trailTolerance: Float = 0.6

    /// Adds a node at `position`. When a walked `trail` (positions since the
    /// previous mark) is given, its corners become junction waypoints so the
    /// edges follow the corridor instead of cutting through walls.
    @discardableResult
    mutating func addNode(name: String, category: POICategory, details: String?,
                          position: SIMD2<Float>, trail: [SIMD2<Float>] = []) -> NavigationPOI {
        if let previous = lastAddedID, !trail.isEmpty,
           let previousPOI = map.pois.first(where: { $0.id == previous }) {
            let corners = PathSimplifier.simplify([previousPOI.planarPosition] + trail + [position],
                                                  tolerance: Self.trailTolerance)
            for corner in corners.dropFirst().dropLast() {
                addWaypoint(at: corner)
            }
        }

        let poi = NavigationPOI(id: uniqueID(for: name),
                                name: name,
                                x: position.x,
                                z: position.y,
                                category: category,
                                details: details?.isEmpty == true ? nil : details)
        map.pois.append(poi)
        if let previous = lastAddedID {
            connect(previous, to: poi.id)
        }
        lastAddedID = poi.id
        return poi
    }

    private mutating func addWaypoint(at position: SIMD2<Float>) {
        let n = map.pois.filter { $0.category == .junction }.count + 1
        let waypoint = NavigationPOI(id: uniqueID(for: "wp-\(n)"), name: "Waypoint \(n)",
                                     x: position.x, z: position.y, category: .junction)
        map.pois.append(waypoint)
        if let previous = lastAddedID {
            connect(previous, to: waypoint.id)
        }
        lastAddedID = waypoint.id
    }

    /// Adds an undirected edge unless one already exists.
    mutating func connect(_ a: String, to b: String) {
        guard a != b, map.pois.contains(where: { $0.id == a }), map.pois.contains(where: { $0.id == b }) else { return }
        let edge = NavigationEdge(from: a, to: b)
        guard !map.edges.contains(where: { $0.matches(edge) }) else { return }
        map.edges.append(edge)
    }

    mutating func removeNode(_ id: String) {
        map.pois.removeAll { $0.id == id }
        map.edges.removeAll { $0.from == id || $0.to == id }
        if lastAddedID == id {
            lastAddedID = map.pois.last?.id
        }
    }

    mutating func updateNode(_ id: String, name: String, category: POICategory, details: String?) {
        guard let index = map.pois.firstIndex(where: { $0.id == id }) else { return }
        map.pois[index].name = name
        map.pois[index].category = category
        map.pois[index].details = details?.isEmpty == true ? nil : details
    }

    /// Renames the map. The server slug is bound separately, at first publish,
    /// so renaming never moves a map's version history.
    /// Ties the map to an Immersal map built on this walk's own poses.
    mutating func setImmersalAlignment(_ alignment: ImmersalAlignment?) {
        map.immersalAlignment = alignment
    }

    mutating func rename(to name: String) {
        map.name = name
    }

    /// Chooses which node the next mark links from (e.g. after walking back to a junction).
    mutating func continueChain(from id: String) {
        guard map.pois.contains(where: { $0.id == id }) else { return }
        lastAddedID = id
    }

    // MARK: - Private

    private func uniqueID(for name: String) -> String {
        let base = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let slug = base.isEmpty ? "node" : base
        var candidate = slug
        var n = 2
        while map.pois.contains(where: { $0.id == candidate }) {
            candidate = "\(slug)-\(n)"
            n += 1
        }
        return candidate
    }
}
