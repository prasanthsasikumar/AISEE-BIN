import Foundation

/// A user request extracted from a speech transcript.
enum VoiceCommand: Equatable {
    case navigate(poiID: String)
    case whereAmI
    case whatsNearby
    case repeatInstruction
    case stop
    case unknown
}

/// Turns free-form transcripts into `VoiceCommand`s. Pure and deterministic.
///
/// Matching strategy, in order:
/// 1. Global phrases (where am I, nearby, repeat, stop).
/// 2. Best-scoring navigable POI by token overlap with its name and aliases,
///    where tokens match on a shared stem (≥ 4 characters) so "orchids" hits
///    "Orchid Display". Ties go to the longer name match.
struct CommandParser {

    private struct Candidate {
        let id: String
        let tokenSets: [[String]]  // name tokens, then each alias's tokens
    }

    private let candidates: [Candidate]

    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "me", "please", "take", "go", "navigate", "bring", "head",
        "where", "is", "are", "find", "i", "want", "get", "walk", "guide", "of", "in", "at", "house",
    ]

    init(pois: [NavigationPOI]) {
        candidates = pois.filter(\.isDestination).map { poi in
            Candidate(id: poi.id, tokenSets: [Self.tokens(poi.name)] + poi.aliases.map(Self.tokens))
        }
    }

    func parse(_ transcript: String) -> VoiceCommand {
        let text = transcript.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .unknown }

        if Self.contains(text, any: ["where am i", "my location", "current location"]) { return .whereAmI }
        if Self.contains(text, any: ["whats around", "what is around", "whats near", "what is near", "nearby", "around me"]) {
            return .whatsNearby
        }
        if Self.contains(text, any: ["repeat", "say that again", "say again", "again"]) { return .repeatInstruction }
        if Self.contains(text, any: ["stop", "cancel", "end navigation", "never mind"]) { return .stop }

        let queryTokens = Self.tokens(text).filter { !Self.stopWords.contains($0) }
        guard !queryTokens.isEmpty else { return .unknown }

        var best: (id: String, score: Int)?
        for candidate in candidates {
            for set in candidate.tokenSets {
                let score = set.filter { token in queryTokens.contains { Self.stemsMatch($0, token) } }.count
                // Accept a full match, any two matching words, or one word of a short (≤2 word) name.
                let accepted = score > 0 && (score == set.count || score >= 2 || set.count <= 2)
                guard accepted else { continue }
                if best == nil || score > best!.score {
                    best = (candidate.id, score)
                }
            }
        }
        return best.map { .navigate(poiID: $0.id) } ?? .unknown
    }

    // MARK: - Helpers

    private static func contains(_ text: String, any phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// "orchids" ~ "orchid", "conservatories" ~ "conservatory". Short words must match exactly.
    private static func stemsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let minLength = min(a.count, b.count)
        guard minLength >= 4 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }
}
