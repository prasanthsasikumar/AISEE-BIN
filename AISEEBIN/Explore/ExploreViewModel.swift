import Foundation
import Observation

/// One Explore visit: pick a time, preview the plan, walk it stop by stop, and
/// ask about anything on the way. Positioning, routing and arrival come from
/// `NavigationViewModel` through its Explore hooks; nothing here is persisted.
@MainActor
@Observable
final class ExploreViewModel {

    enum Phase: Equatable {
        case welcome, preview, walking
        case arrived(stopIndex: Int)
        case complete
    }

    enum AskState: Equatable {
        case idle
        case thinking(question: String)
        case answering(question: String, text: String)
        case failed(question: String)
    }

    static let failureText = "Sorry, I couldn't answer that just now."
    static let timeChoices: [Double] = [10, 20, 30, 45]

    let nav: NavigationViewModel
    @ObservationIgnored private let client: ExploreClient

    private(set) var phase: Phase = .welcome
    private(set) var budgetMinutes: Double = 20
    private(set) var plan: TourPlan?
    private(set) var planner: TourPlanner
    /// Index into `plan.stopIDs` of the stop being walked to; `stopIDs.count` means the end.
    private(set) var stopIndex = 0
    private(set) var clock: VisitClock?
    private(set) var isPlanningFromSpeech = false
    private(set) var message: String?
    private var skippedOffers: Set<String> = []

    private(set) var askState: AskState = .idle
    var isAskOpen = false
    @ObservationIgnored private var history = AskHistory()
    @ObservationIgnored private var askTask: Task<Void, Never>?
    private enum ListeningFor { case question, plan }
    @ObservationIgnored private var listeningFor: ListeningFor?

    /// Turn-by-turn speech; off by default for sighted visitors.
    var voiceDirections = false {
        didSet { nav.quietGuidance = !voiceDirections }
    }

    init(nav: NavigationViewModel, client: ExploreClient = ExploreClient()) {
        self.nav = nav
        self.client = client
        self.planner = TourPlanner(map: nav.displayMap)
    }

    // MARK: - Map

    var map: NavigationMap { nav.displayMap }
    /// A start, and somewhere to go: a stop, or an end that is not the start.
    var hasTour: Bool {
        planner.startID != nil && (!planner.candidates.isEmpty || planner.endID != planner.startID)
    }
    var addableStops: [NavigationPOI] {
        planner.candidates.filter { !(plan?.stopIDs.contains($0.id) ?? false) }.sorted { $0.name < $1.name }
    }
    func poi(_ id: String) -> NavigationPOI? { map.pois.first { $0.id == id } }

    /// Every node the whole tour walks through, start to end, for the preview map.
    var tourPath: [String] {
        guard let plan else { return [] }
        let engine = PathfindingEngine(map: map)
        let route = [plan.startID] + plan.stopIDs + [plan.endID]
        var path: [String] = [plan.startID]
        for (a, b) in zip(route, route.dropFirst()) where a != b {
            path += engine.findPath(from: a, to: b).dropFirst().map(engine.name(of:))
        }
        return path
    }

    /// Called when the screen appears: Explore is quiet and plans on the current map.
    func enter() {
        nav.quietGuidance = !voiceDirections
        if phase == .welcome { planner = TourPlanner(map: nav.displayMap) }
    }

    // MARK: - Planning

    func choose(minutes: Double) {
        planner = TourPlanner(map: nav.displayMap)
        budgetMinutes = minutes
        plan = planner.plan(TourRequest(minutes: minutes))
        message = nil
        if plan != nil { phase = .preview }
    }

    /// "Or just say it": listens once, then asks the proxy to read the request.
    func listenForTime() {
        listen(for: .plan)
    }

    func plan(fromSpeech utterance: String) async {
        guard !utterance.isEmpty else { return }
        isPlanningFromSpeech = true
        defer { isPlanningFromSpeech = false }
        planner = TourPlanner(map: nav.displayMap)
        do {
            let request = try await client.plan(utterance: utterance, exhibits: planner.candidates)
            budgetMinutes = request.minutes
            plan = planner.plan(request)
            message = nil
            if plan != nil { phase = .preview }
        } catch {
            message = "Sorry, I didn't catch that. Tap a time instead."
        }
    }

    func drop(_ id: String) {
        guard let plan else { return }
        self.plan = planner.removing(id, from: plan)
    }

    func add(_ id: String) {
        guard let plan else { return }
        self.plan = planner.adding(id, to: plan)
    }

    func backToWelcome() {
        phase = .welcome
        plan = nil
    }

    // MARK: - Walking

    var currentTargetID: String? {
        guard let plan else { return nil }
        return stopIndex < plan.stopIDs.count ? plan.stopIDs[stopIndex] : plan.endID
    }
    var isHeadingToEnd: Bool { (plan?.stopIDs.count ?? 0) <= stopIndex }

    func start() {
        guard let plan else { return }
        nav.quietGuidance = !voiceDirections
        nav.onArrived = { [weak self] id in self?.arrived(at: id) }
        clock = VisitClock(plan: plan, schedule: planner.schedule(plan), startedAt: Date())
        stopIndex = 0
        skippedOffers = []
        phase = .walking
        goToTarget()
    }

    func nextStop() {
        nav.guidance.stopSpeaking()
        stopIndex += 1
        phase = .walking
        goToTarget()
    }

    func endVisit() {
        nav.stopNavigation()
        nav.onArrived = nil
        phase = .complete
    }

    func newVisit() {
        nav.stopNavigation()
        nav.onArrived = nil
        plan = nil
        clock = nil
        phase = .welcome
    }

    func minutesLeft(now: Date) -> Double {
        clock?.minutesLeft(budget: budgetMinutes, now: now) ?? budgetMinutes
    }

    /// The stop to offer skipping, if the visitor is running late and has not said no to it.
    func lateOffer(now: Date) -> NavigationPOI? {
        guard phase == .walking, let id = clock?.lateOffer(map: map, now: now, nextIndex: stopIndex),
              !skippedOffers.contains(id) else { return nil }
        return poi(id)
    }

    func keep(_ id: String) { skippedOffers.insert(id) }

    func skip(_ id: String) {
        guard var plan, let index = plan.stopIDs.firstIndex(of: id) else { return }
        plan.stopIDs.remove(at: index)
        self.plan = planner.evaluate(stopIDs: plan.stopIDs) ?? plan
        if let clock, let newPlan = self.plan {
            self.clock = VisitClock(plan: newPlan, schedule: planner.schedule(newPlan), startedAt: clock.startedAt)
        }
        if index == stopIndex { goToTarget() } else if index < stopIndex { stopIndex -= 1 }
    }

    private func goToTarget() {
        guard let target = currentTargetID else { return }
        nav.navigate(to: target)
    }

    private func arrived(at id: String) {
        guard phase == .walking, id == currentTargetID, let plan else { return }
        if stopIndex < plan.stopIDs.count {
            clock?.arrived(at: stopIndex, now: Date())
            phase = .arrived(stopIndex: stopIndex)
            if let poi = poi(id) {
                nav.guidance.speak(poi.details?.isEmpty == false ? poi.details! : "This is \(poi.name).", interrupt: true)
            }
        } else {
            nav.onArrived = nil
            phase = .complete
            nav.guidance.speak("That's your visit. Thanks for coming to the Flower Dome.", interrupt: true)
        }
    }

    #if DEBUG
    /// Simulator screenshots only.
    func demo(_ phase: String) {
        choose(minutes: 20)
        if phase == "complete" { self.phase = .complete }
        if phase == "walking" { start() }
        if phase == "arrived", plan?.stopIDs.isEmpty == false { self.phase = .arrived(stopIndex: 0) }
    }
    #endif

    // MARK: - Asking

    var isListening: Bool { nav.isListening }
    var liveTranscript: String { nav.recognizer.transcript }

    func openAsk() {
        isAskOpen = true
        ask()
    }

    /// Tap to start listening; tap again to send what was heard.
    func ask() {
        if nav.isListening {
            nav.recognizer.stopListening(deliver: true)
            return
        }
        askTask?.cancel()
        nav.guidance.stopSpeaking()
        askState = .idle
        listen(for: .question)
    }

    func closeAsk() {
        askTask?.cancel()
        askTask = nil
        if nav.isListening { nav.recognizer.stopListening(deliver: false) }
        nav.guidance.stopSpeaking()
        askState = .idle
        isAskOpen = false
    }

    private func listen(for purpose: ListeningFor) {
        listeningFor = purpose
        nav.transcriptOverride = { [weak self] text in self?.heard(text) }
        nav.toggleListening()
    }

    private func heard(_ text: String) {
        let purpose = listeningFor
        listeningFor = nil
        nav.transcriptOverride = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch purpose {
        case .plan: Task { await plan(fromSpeech: text) }
        case .question, nil: send(question: text)
        }
    }

    private func send(question: String) {
        askState = .thinking(question: question)
        let jpeg = nav.arManager.session.currentFrame.flatMap { FrameGrabber.jpeg(from: $0) }
        let pose = nav.mapPose
        let places = AskContext.places(map: map, position: pose?.position, heading: pose?.heading ?? 0)
        let stream = client.ask(question: question, jpeg: jpeg, mapSlug: nav.mapSlug, places: places,
                                venueInfo: map.venueInfo, history: history.recent(now: Date()))
        askTask = Task { [weak self] in
            var answer = ""
            var unspoken = ""
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled else { return }
                    answer += chunk
                    unspoken += chunk
                    self.askState = .answering(question: question, text: answer)
                    let (ready, rest) = Self.splitSentences(unspoken)
                    if !ready.isEmpty { self.nav.guidance.speak(ready, interrupt: false) }
                    unspoken = rest
                }
                guard let self, !Task.isCancelled else { return }
                let tail = unspoken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { self.nav.guidance.speak(tail, interrupt: false) }
                if answer.isEmpty { throw ExploreClientError.timeout }
                self.history.add(q: question, a: answer, at: Date())
            } catch {
                guard let self, !Task.isCancelled else { return }
                if answer.isEmpty {
                    self.askState = .failed(question: question)
                    self.nav.guidance.speak(Self.failureText, interrupt: true)
                }
            }
        }
    }

    /// Splits off whole sentences so speech can start before the answer is complete.
    nonisolated static func splitSentences(_ text: String) -> (ready: String, rest: String) {
        var lastEnd: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            if ".!?".contains(text[i]), next < text.endIndex, text[next].isWhitespace { lastEnd = next }
            i = next
        }
        guard let lastEnd else { return ("", text) }
        return (text[..<lastEnd].trimmingCharacters(in: .whitespaces), String(text[lastEnd...]))
    }
}
