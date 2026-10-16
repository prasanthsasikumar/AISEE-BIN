import Foundation

/// Places added on site from the Field Test sheet ("Add here"): an id made
/// from the name that no other place has, and the edit that puts the new
/// places and the path between them into the newest server version.
enum PlaceAdder {
    /// "Door B" → `door-b`; a second "Door B" → `door-b-2`. The slug rule is
    /// the one map names use, so ids look like the editor's.
    static func id(for name: String, taken: Set<String>) -> String {
        let hasContent = name.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        let base = hasContent ? ServerConfig.slug(from: name) : "place"
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// Appends `places` and `edges`. The edit runs on whatever version is
    /// newest when it is published, so an id that someone else used meanwhile
    /// is renumbered and the edges follow. An edge already in the map, or one
    /// whose ends are not both in it, is left out.
    static func apply(places: [NavigationPOI], edges: [NavigationEdge], to graph: inout NavigationMap) {
        var taken = Set(graph.pois.map(\.id))
        var renamed: [String: String] = [:]
        for place in places {
            var added = place
            if taken.contains(place.id) {
                let newID = id(for: place.name, taken: taken)
                renamed[place.id] = newID
                added = NavigationPOI(id: newID, name: place.name, x: place.x, z: place.z, category: place.category,
                                      details: place.details, aliases: place.aliases,
                                      customAnnounceRadius: place.customAnnounceRadius)
            }
            taken.insert(added.id)
            graph.pois.append(added)
        }
        for edge in edges {
            let e = NavigationEdge(from: renamed[edge.from] ?? edge.from, to: renamed[edge.to] ?? edge.to)
            guard taken.contains(e.from), taken.contains(e.to), e.from != e.to,
                  !graph.edges.contains(where: { $0.matches(e) }) else { continue }
            graph.edges.append(e)
        }
    }
}
