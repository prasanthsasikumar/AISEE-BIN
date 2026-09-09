import Foundation
import simd

/// Coarse side of the user a thing is on, for speech ("on your left").
enum RelativeSide: Equatable {
    case ahead, left, right, behind

    /// - Parameter relativeAngle: radians in (-π, π]; positive = right.
    init(relativeAngle: Float) {
        let degrees = relativeAngle * 180 / .pi
        switch degrees {
        case -45...45:      self = .ahead
        case 45..<135:      self = .right
        case -135 ..< -45:  self = .left
        default:            self = .behind
        }
    }

    var phrase: String {
        switch self {
        case .ahead:  return "ahead"
        case .left:   return "on your left"
        case .right:  return "on your right"
        case .behind: return "behind you"
        }
    }
}

struct ProximityAnnouncement: Equatable {
    let poi: NavigationPOI
    let side: RelativeSide
    let distance: Float

    var spokenText: String {
        let lead = poi.category == .hazard ? "Caution: \(poi.name)" : poi.name
        let base = "\(lead) \(side.phrase)."
        guard let details = poi.details, !details.isEmpty else { return base }
        return "\(base) \(details)"
    }
}

/// Emits one announcement when the user enters an exhibit's or hazard's
/// `announceRadius`, and re-arms only after they have moved beyond 1.5× that
/// radius, so pacing back and forth at the boundary does not repeat it.
struct ProximityAnnouncer {

    private let pois: [NavigationPOI]
    private var armed: [String: Bool]

    init(pois: [NavigationPOI]) {
        self.pois = pois.filter { $0.announceRadius > 0 }
        armed = Dictionary(uniqueKeysWithValues: self.pois.map { ($0.id, true) })
    }

    mutating func update(position: SIMD2<Float>, heading: Float) -> [ProximityAnnouncement] {
        var announcements: [ProximityAnnouncement] = []
        for poi in pois {
            let distance = simd_distance(position, poi.planarPosition)
            let radius = poi.announceRadius
            if distance <= radius {
                if armed[poi.id] == true {
                    armed[poi.id] = false
                    let angle = NavigationGeometry.relativeBearing(from: position, heading: heading, to: poi.planarPosition)
                    announcements.append(ProximityAnnouncement(poi: poi,
                                                               side: RelativeSide(relativeAngle: angle),
                                                               distance: distance))
                }
            } else if distance > radius * 1.5 {
                armed[poi.id] = true
            }
        }
        return announcements
    }
}
