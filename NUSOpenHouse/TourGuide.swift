import Foundation
import Observation

/// What the visitor is doing: the tour of every location in order, or one place.
@MainActor
@Observable
final class TourGuide {
    enum Plan: Equatable {
        case tour
        case single(String)
    }

    enum Phase: Equatable {
        case home
        /// Walking (or waiting for a position) toward `stops[index]`.
        case leading
        /// At `stops[index]`, showing its card.
        case arrived
        /// Tour over.
        case finished
    }

    let viewModel: NavigationViewModel
    private(set) var plan: Plan = .tour
    private(set) var phase: Phase = .home
    private(set) var stops: [NavigationPOI] = []
    private(set) var index = 0
    /// Spoken guidance on or off (off by default: open-house halls are loud and shared).
    var voiceOn: Bool = UserDefaults.standard.bool(forKey: "nus.voice") {
        didSet {
            UserDefaults.standard.set(voiceOn, forKey: "nus.voice")
            viewModel.quietGuidance = !voiceOn
        }
    }

    init(viewModel: NavigationViewModel) {
        self.viewModel = viewModel
        viewModel.quietGuidance = !voiceOn
        viewModel.onArrived = { [weak self] id in self?.arrived(at: id) }
    }

    /// The open-house locations in the order they were marked on the map
    /// (the tour order). The tour's start point, if set, is not a stop.
    var places: [NavigationPOI] {
        let map = viewModel.displayMap
        return map.pois.filter { $0.category == .destination || $0.category == .exhibit }
            .filter { $0.id != map.tourStart }
    }

    var current: NavigationPOI? { stops.indices.contains(index) ? stops[index] : nil }
    var isTour: Bool { plan == .tour }
    var isLastStop: Bool { index >= stops.count - 1 }

    func levelName(of id: String) -> String? { viewModel.engine.levels.levelName(of: id) }

    // MARK: - Actions

    func startTour() {
        plan = .tour
        stops = places
        index = 0
        viewModel.usage.log("tour.start", ["stops": .number(Double(stops.count))])
        leadToCurrent()
    }

    func go(to poi: NavigationPOI) {
        plan = .single(poi.id)
        stops = [poi]
        index = 0
        leadToCurrent()
    }

    func nextStop() {
        guard isTour, !isLastStop else { finish(); return }
        index += 1
        leadToCurrent()
    }

    func skipStop() {
        viewModel.usage.log("tour.skip", ["id": .string(current?.id ?? "")])
        nextStop()
    }

    func exit() {
        if phase == .leading || phase == .arrived, isTour {
            viewModel.usage.log("tour.abandon", ["at": .number(Double(index))])
        }
        viewModel.stopNavigation()
        phase = .home
        stops = []
        index = 0
    }

    private func finish() {
        viewModel.stopNavigation()
        if isTour { viewModel.usage.log("tour.end", ["stops": .number(Double(stops.count))]) }
        phase = isTour ? .finished : .home
        if !isTour { stops = [] }
    }

    private func leadToCurrent() {
        guard let stop = current else { finish(); return }
        phase = .leading
        viewModel.navigate(to: stop.id)
    }

    private func arrived(at id: String) {
        guard phase == .leading, current?.id == id else { return }
        if isTour { viewModel.usage.log("tour.stop_arrived", ["id": .string(id), "index": .number(Double(index))]) }
        phase = .arrived
    }
}
