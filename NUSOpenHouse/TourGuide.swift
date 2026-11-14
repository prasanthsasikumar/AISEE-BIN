import Foundation
import Observation
import simd

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
    /// The tour was started before the phone knew where it is: the first stop
    /// is picked (the nearest one) as soon as positioning is reliable.
    private(set) var startPending = false
    /// A short line confirming what just changed ("Skipped Seating. Next: MPH 2"),
    /// shown for a few seconds.
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// Spoken guidance on or off (off by default: the halls are loud and shared).
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

    /// The tour's locations in the order they were marked on the map
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

    /// Starts the tour where the visitor is: the nearest stop comes first and
    /// the rest follow in tour order, wrapping round.
    func startTour() {
        plan = .tour
        stops = places
        index = 0
        viewModel.usage.log("tour.start", ["stops": .number(Double(stops.count))])
        startPending = true
        phase = .leading
        if viewModel.localizationStatus.isReliable { beginFromHere() } else { viewModel.stopNavigation() }
    }

    /// Called when positioning becomes reliable.
    func positionIsReliable() {
        guard startPending, phase == .leading, isTour else { return }
        beginFromHere()
    }

    private func beginFromHere() {
        startPending = false
        let here = NavigationGeometry.planarPosition(of: viewModel.currentTransform)
        let height = viewModel.currentTransform.columns.3.y
        if let first = Self.nearestStopIndex(stops: stops.map(\.id), from: here, height: height, engine: viewModel.engine), first > 0 {
            stops = Array(stops[first...] + stops[..<first])
        }
        viewModel.usage.log("tour.start_from", ["id": .string(stops.first?.id ?? "")])
        leadToCurrent()
    }

    /// The stop closest to the visitor: planar distance plus a penalty for
    /// being on another floor (the same weighting as the route search).
    static func nearestStopIndex(stops: [String], from here: SIMD2<Float>, height: Float, engine: PathfindingEngine) -> Int? {
        var best: (Int, Float)?
        for (i, id) in stops.enumerated() {
            guard let node = engine.node(named: id) else { continue }
            var d = simd_distance(node.position, here)
            if let y = engine.levels.heights[id] { d += PathfindingEngine.heightWeight * abs(y - height) }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
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

    /// Moves on to the next stop and says so: the way to the next place often
    /// starts along the same corridor, so nothing else on screen shows the skip.
    func skipStop() {
        let skipped = current
        viewModel.usage.log("tour.skip", ["id": .string(skipped?.id ?? "")])
        nextStop()
        guard phase == .leading, let skipped, let next = current else { return }
        show(notice: Self.skipNotice(skipped: skipped.name, next: next.name, level: levelName(of: next.id)))
    }

    static func skipNotice(skipped: String, next: String, level: String?) -> String {
        "Skipped \(skipped). Next: \(next)" + (level.map { ", \($0)" } ?? "")
    }

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    func exit() {
        if phase == .leading || phase == .arrived, isTour {
            viewModel.usage.log("tour.abandon", ["at": .number(Double(index))])
        }
        viewModel.stopNavigation()
        clearNotice()
        phase = .home
        stops = []
        index = 0
        startPending = false
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
        clearNotice()
        phase = .arrived
    }
}
