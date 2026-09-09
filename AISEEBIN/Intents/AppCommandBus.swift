import Foundation

/// Commands that arrive from outside the UI (Siri, Action Button, Shortcuts).
enum AppCommand: Equatable {
    case startListening
    case navigate(poiID: String)
}

/// Hands App Intent invocations to the live view model. Commands posted before
/// a handler exists (cold launch from Siri) are queued and flushed on attach.
@MainActor
final class AppCommandBus {

    static let shared = AppCommandBus()

    private var pending: [AppCommand] = []

    var handler: ((AppCommand) -> Void)? {
        didSet { flush() }
    }

    func post(_ command: AppCommand) {
        pending.append(command)
        flush()
    }

    private func flush() {
        guard let handler else { return }
        let queued = pending
        pending.removeAll()
        queued.forEach(handler)
    }
}
