import Foundation

/// Which glasses the app talks to. AiSee (Realtek SDK) is the original; Ray-Ban
/// Meta goes through Meta's Wearables Device Access Toolkit (`MetaGlassKit`).
enum GlassesKind: String, CaseIterable, Identifiable {
    case aisee, rayban

    static let key = "glasses.kind"

    var id: String { rawValue }

    static func load(from defaults: UserDefaults = .standard) -> GlassesKind {
        defaults.string(forKey: key).flatMap(GlassesKind.init(rawValue:)) ?? .aisee
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    var label: String {
        self == .aisee ? "AiSee" : "Ray-Ban Meta"
    }
}
