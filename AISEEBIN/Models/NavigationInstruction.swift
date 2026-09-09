import Foundation

/// Coarse turn bucket derived from the signed angle between the user's heading
/// and the bearing to the next node. Positive angles are to the right.
enum TurnDirection: String, Hashable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn

    /// - Parameter relativeAngle: radians in (-π, π]; positive = clockwise = right.
    init(relativeAngle: Float) {
        let degrees = abs(relativeAngle) * 180 / .pi
        let right = relativeAngle > 0
        switch degrees {
        case ..<15:   self = .straight
        case ..<45:   self = right ? .slightRight : .slightLeft
        case ..<120:  self = right ? .right : .left
        case ..<160:  self = right ? .sharpRight : .sharpLeft
        default:      self = .uTurn
        }
    }

    /// Phrase used in the spoken prompt, e.g. "turn slight right".
    var spokenPhrase: String {
        switch self {
        case .straight:    return "continue straight"
        case .slightLeft:  return "turn slight left"
        case .left:        return "turn left"
        case .sharpLeft:   return "turn sharp left"
        case .slightRight: return "turn slight right"
        case .right:       return "turn right"
        case .sharpRight:  return "turn sharp right"
        case .uTurn:       return "turn around"
        }
    }

    var isLeft: Bool  { [.slightLeft, .left, .sharpLeft].contains(self) }
    var isRight: Bool { [.slightRight, .right, .sharpRight].contains(self) }
}

/// One fully-resolved guidance step: what to do, how far away it is, and where it leads.
struct NavigationInstruction: Hashable {
    let direction: TurnDirection
    /// Metres from the user to the next node.
    let distance: Float
    let nextNodeName: String
    /// `true` when the next node is the destination itself.
    let isFinal: Bool

    private var roundedMetres: Int { max(1, Int(distance.rounded())) }
    private var metresWord: String { roundedMetres == 1 ? "meter" : "meters" }

    /// Full sentence for `AVSpeechSynthesizer`.
    var spokenText: String {
        if isFinal {
            let capitalised = direction.spokenPhrase.prefix(1).uppercased() + direction.spokenPhrase.dropFirst()
            return "\(capitalised). The \(nextNodeName) is \(roundedMetres) \(metresWord) ahead."
        }
        return "In \(roundedMetres) \(metresWord), \(direction.spokenPhrase) toward the \(nextNodeName)."
    }

    /// Short line for the on-screen banner.
    var bannerText: String {
        let verb = direction.spokenPhrase.prefix(1).uppercased() + direction.spokenPhrase.dropFirst()
        return isFinal ? "\(verb) to \(nextNodeName)" : "\(verb) toward \(nextNodeName)"
    }

    var distanceText: String { "\(roundedMetres) m" }
}
