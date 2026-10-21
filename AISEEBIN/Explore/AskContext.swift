import Foundation
import simd

/// A place near the visitor, as sent with a question.
struct AskPlace: Codable, Equatable {
    let id: String
    let name: String
    let details: String?
    let about: String?
    let distance: Float
    /// The nearest place roughly in front of the camera.
    let inView: Bool
}

/// One earlier question and answer in this visit.
struct AskTurn: Codable, Equatable {
    let q: String
    let a: String
}

/// The last few questions, so "how old is it?" knows what "it" is.
struct AskHistory {
    static let maxTurns = 3
    static let maxAge: TimeInterval = 300

    private var turns: [(turn: AskTurn, at: Date)] = []

    mutating func add(q: String, a: String, at date: Date) {
        turns.append((AskTurn(q: q, a: a), date))
        if turns.count > Self.maxTurns { turns.removeFirst(turns.count - Self.maxTurns) }
    }

    func recent(now: Date) -> [AskTurn] {
        turns.filter { now.timeIntervalSince($0.at) <= Self.maxAge }.map(\.turn)
    }
}

enum AskContext {
    /// Half-angle of "in front of the camera".
    static let inViewHalfAngle: Float = .pi / 6

    /// Named places within `radius` metres, nearest first; junctions never count.
    /// Empty when the visitor's position is not known.
    static func places(map: NavigationMap, position: SIMD2<Float>?, heading: Float,
                       radius: Float = 15, limit: Int = 4) -> [AskPlace] {
        guard let position else { return [] }
        let near = map.pois
            .filter { $0.category != .junction }
            .map { ($0, simd_distance($0.planarPosition, position)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
        let inViewID = near.first { poi, distance in
            distance < 0.01 || abs(NavigationGeometry.relativeBearing(from: position, heading: heading,
                                                                      to: poi.planarPosition)) <= inViewHalfAngle
        }?.0.id
        return near.map { poi, distance in
            AskPlace(id: poi.id, name: poi.name, details: poi.details, about: poi.about,
                     distance: distance, inView: poi.id == inViewID)
        }
    }
}
