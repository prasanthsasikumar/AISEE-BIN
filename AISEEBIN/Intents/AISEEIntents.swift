import AppIntents
import Foundation

/// A destination exposed to Siri and Shortcuts. Backed by the saved map (or the
/// bundled sample) so "Take me to the Orchid Display" resolves by name.
struct DestinationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    static var defaultQuery = DestinationQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func all() -> [DestinationEntity] {
        let map = MapStore().loadMap() ?? SampleGreenhouseMap.map
        return map.pois.filter(\.isDestination).map { DestinationEntity(id: $0.id, name: $0.name) }
    }
}

struct DestinationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [DestinationEntity] {
        DestinationEntity.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [DestinationEntity] {
        DestinationEntity.all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [DestinationEntity] {
        DestinationEntity.all()
    }
}

/// Bind this to the Action Button (Settings → Action Button → Shortcut → AISEE-BIN
/// → Listen) for a physical push-to-talk trigger on a chest mount.
struct StartListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Listen for a command"
    static var description = IntentDescription("Opens AISEE-BIN and listens for a spoken navigation command.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCommandBus.shared.post(.startListening)
        return .result()
    }
}

/// "Hey Siri, take me to the Restrooms in AISEE-BIN."
struct NavigateToIntent: AppIntent {
    static var title: LocalizedStringResource = "Navigate to a destination"
    static var description = IntentDescription("Starts hands-free guidance to a place in the current map.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: DestinationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCommandBus.shared.post(.navigate(poiID: destination.id))
        return .result()
    }
}

struct AISEEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Listen in \(.applicationName)",
                "\(.applicationName) listen",
                "Start listening in \(.applicationName)",
            ],
            shortTitle: "Listen",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: NavigateToIntent(),
            phrases: [
                "Take me to \(\.$destination) in \(.applicationName)",
                "Navigate to \(\.$destination) in \(.applicationName)",
                "Go to \(\.$destination) in \(.applicationName)",
            ],
            shortTitle: "Navigate",
            systemImageName: "figure.walk"
        )
    }
}
