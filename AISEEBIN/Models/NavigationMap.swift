import Foundation
import simd

/// What a node is for. Drives routing eligibility and passive commentary.
enum POICategory: String, Codable, CaseIterable, Identifiable {
    /// A place the user can ask to be taken to (entrance, restrooms, a house).
    case destination
    /// A corridor intersection used only for routing.
    case junction
    /// A plant or display: navigable *and* announced when passed.
    case exhibit
    /// Steps, wet floor, low branches: never a destination, always announced.
    case hazard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .destination: return "Destination"
        case .junction:    return "Junction"
        case .exhibit:     return "Exhibit"
        case .hazard:      return "Hazard"
        }
    }
}

/// A point of interest or intersection on the greenhouse floor plan.
///
/// Coordinates are metres in the **ARKit world frame of the saved `ARWorldMap`**:
/// `x` points right and `z` points *toward* the user at the map origin, so a
/// node straight ahead of the origin has a negative `z`. When a world map is
/// loaded, `x`/`z` are overwritten from the matching `ARAnchor`; the stored
/// values are a fallback for tests and for maps without anchors.
struct NavigationPOI: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var x: Float
    var z: Float
    var category: POICategory = .destination
    /// Spoken when the user asks about, or walks past, this node.
    var details: String?
    /// Extra spoken names for voice matching ("bathroom" → Restrooms).
    var aliases: [String] = []
    /// Announce radius set in the web editor, metres; nil means the default.
    /// Stored as `announceRadius` in the map JSON.
    var customAnnounceRadius: Float?

    // Explore mode (sighted visitors). All optional; written in the web editor.
    /// Minutes a visitor typically spends here; nil means `visitMinutes`' default.
    var minutes: Double?
    /// 1 must see, 2 good, 3 if there's time, 0 not a tour stop; nil means 2.
    var highlight: Int?
    /// Interest tags matched against what the visitor says they like.
    var tags: [String] = []
    /// Longer facts the guide may use to answer questions about this place.
    var about: String?
    /// Optional photo shown on the stop card.
    var photo: String?

    var visitMinutes: Double { minutes ?? 3 }
    var highlightLevel: Int { highlight ?? 2 }

    init(id: String, name: String, x: Float, z: Float,
         category: POICategory = .destination, details: String? = nil, aliases: [String] = [],
         customAnnounceRadius: Float? = nil) {
        self.id = id
        self.name = name
        self.x = x
        self.z = z
        self.category = category
        self.details = details
        self.aliases = aliases
        self.customAnnounceRadius = customAnnounceRadius
    }

    var planarPosition: SIMD2<Float> { SIMD2(x, z) }

    /// Nodes the user can pick or ask for by voice.
    var isDestination: Bool { category == .destination || category == .exhibit }

    /// Used when a place has no radius of its own.
    static let defaultAnnounceRadius: Float = 2.5
    /// A radius outside this range is treated as a typo and ignored.
    static let announceRadiusRange: ClosedRange<Float> = 0.5...20

    /// Radius (metres) within which the node is announced while walking; 0 = never.
    /// Only exhibits and hazards are announced; the editor may set their radius.
    var announceRadius: Float {
        guard category == .exhibit || category == .hazard else { return 0 }
        if let custom = customAnnounceRadius, Self.announceRadiusRange.contains(custom) { return custom }
        return Self.defaultAnnounceRadius
    }

    // Custom decoding so JSON written by hand may omit the optional fields.
    private enum CodingKeys: String, CodingKey {
        case id, name, x, z, category, details, aliases
        case customAnnounceRadius = "announceRadius"
        case minutes, highlight, tags, about, photo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        x = try c.decode(Float.self, forKey: .x)
        z = try c.decode(Float.self, forKey: .z)
        category = try c.decodeIfPresent(POICategory.self, forKey: .category) ?? .destination
        details = try c.decodeIfPresent(String.self, forKey: .details)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        customAnnounceRadius = try? c.decodeIfPresent(Float.self, forKey: .customAnnounceRadius)
        minutes = try? c.decodeIfPresent(Double.self, forKey: .minutes)
        highlight = try? c.decodeIfPresent(Int.self, forKey: .highlight)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        about = try c.decodeIfPresent(String.self, forKey: .about)
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(x, forKey: .x)
        try c.encode(z, forKey: .z)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encode(aliases, forKey: .aliases)
        try c.encodeIfPresent(customAnnounceRadius, forKey: .customAnnounceRadius)
        try c.encodeIfPresent(minutes, forKey: .minutes)
        try c.encodeIfPresent(highlight, forKey: .highlight)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encodeIfPresent(about, forKey: .about)
        try c.encodeIfPresent(photo, forKey: .photo)
    }
}

/// An undirected walkable connection between two nodes. Cost is Euclidean distance.
struct NavigationEdge: Hashable, Codable {
    let from: String
    let to: String

    /// Same undirected edge regardless of direction.
    func matches(_ other: NavigationEdge) -> Bool {
        (from == other.from && to == other.to) || (from == other.to && to == other.from)
    }
}

/// A complete topological map of one indoor space.
struct NavigationMap: Codable, Equatable {
    var name: String
    var pois: [NavigationPOI]
    var edges: [NavigationEdge]
    /// How Immersal map space maps onto these coordinates, once a phone walk has
    /// measured it. Absent on maps that have never been aligned; glasses mode
    /// needs it, phone mode ignores it. The web editor round-trips it untouched.
    var immersalAlignment: ImmersalAlignment?
    /// Explore mode: where a timed tour starts and ends (POI ids), and general
    /// venue facts the guide may use. Optional; set in the web editor.
    var tourStart: String?
    var tourEnd: String?
    var venueInfo: String?

    init(name: String, pois: [NavigationPOI], edges: [NavigationEdge],
         immersalAlignment: ImmersalAlignment? = nil) {
        self.name = name
        self.pois = pois
        self.edges = edges
        self.immersalAlignment = immersalAlignment
    }

    private enum CodingKeys: String, CodingKey { case name, pois, edges, immersalAlignment, tourStart, tourEnd, venueInfo }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        pois = try c.decode([NavigationPOI].self, forKey: .pois)
        edges = try c.decode([NavigationEdge].self, forKey: .edges)
        immersalAlignment = try c.decodeIfPresent(ImmersalAlignment.self, forKey: .immersalAlignment)
        tourStart = try c.decodeIfPresent(String.self, forKey: .tourStart)
        tourEnd = try c.decodeIfPresent(String.self, forKey: .tourEnd)
        venueInfo = try c.decodeIfPresent(String.self, forKey: .venueInfo)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(pois, forKey: .pois)
        try c.encode(edges, forKey: .edges)
        try c.encodeIfPresent(immersalAlignment, forKey: .immersalAlignment)
        try c.encodeIfPresent(tourStart, forKey: .tourStart)
        try c.encodeIfPresent(tourEnd, forKey: .tourEnd)
        try c.encodeIfPresent(venueInfo, forKey: .venueInfo)
    }
}
