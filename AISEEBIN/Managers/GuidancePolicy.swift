import Foundation

/// Tunable distances and timings for guidance. Metres and seconds.
struct GuidanceThresholds {
    /// Announce the upcoming turn when the next node is this close.
    var approachDistance: Float = 3.0
    /// Treat the node as reached when this close.
    var arrivalDistance: Float = 1.5
    /// Consider the user off-route beyond this distance from the current leg.
    var offRouteDistance: Float = 2.5
    /// Minimum gap between two non-urgent spoken prompts.
    var minSpeechInterval: TimeInterval = 4
    /// Reassurance cadence while walking a long leg.
    var progressReminderInterval: TimeInterval = 12
    /// Cadence for repeating "off route" / "relocalizing" warnings.
    var offRouteRepeatInterval: TimeInterval = 8
}

/// What the guidance layer should do right now. The `GuidanceManager` maps each
/// cue to speech plus a haptic pattern.
enum GuidanceCue: Equatable {
    /// The user is inside the approach radius of the next node: pre-announce the turn.
    case approaching(NavigationInstruction)
    /// The user just reached a node: confirm and announce the following instruction.
    case nodeReached(NavigationInstruction)
    /// The destination (display name) has been reached.
    case arrived(String)
    /// Periodic reassurance on a long leg.
    case progress(NavigationInstruction)
    case offRoute
    case relocalizing
}

/// Pure throttling logic: decides *whether* to speak, never *how*.
///
/// Rules, in priority order:
/// 1. Arrival and node-reached cues always fire (they are one-shot by construction).
/// 2. Tracking loss and off-route warnings repeat at `offRouteRepeatInterval`.
/// 3. The approach announcement fires once per node.
/// 4. Otherwise a progress reminder fires every `progressReminderInterval`.
/// All non-urgent speech additionally respects `minSpeechInterval`.
struct GuidancePolicy {

    let thresholds: GuidanceThresholds

    /// `nil` until the first evaluation of a route; the route-start announcement
    /// is spoken by the view model, so the reminder clock starts from there.
    private var lastSpeechTime: TimeInterval?
    private var lastWarningTime: TimeInterval = -.greatestFiniteMagnitude
    private var announcedApproachFor: String?

    init(thresholds: GuidanceThresholds) {
        self.thresholds = thresholds
    }

    /// Clears per-route memory. Call when a new route starts.
    mutating func reset() {
        lastSpeechTime = nil
        lastWarningTime = -.greatestFiniteMagnitude
        announcedApproachFor = nil
    }

    mutating func evaluate(instruction: NavigationInstruction,
                           routeEvent: RouteEvent,
                           isOffRoute: Bool,
                           trackingReliable: Bool,
                           now: TimeInterval) -> GuidanceCue? {

        let lastSpeech = lastSpeechTime ?? now
        if lastSpeechTime == nil { lastSpeechTime = now }

        switch routeEvent {
        case .arrived(let name):
            lastSpeechTime = now
            return .arrived(name)
        case .reachedNode:
            lastSpeechTime = now
            announcedApproachFor = nil
            return .nodeReached(instruction)
        case .none:
            break
        }

        if !trackingReliable {
            return warningIfDue(.relocalizing, now: now)
        }
        if isOffRoute {
            return warningIfDue(.offRoute, now: now)
        }

        let approachKey = instruction.nextNodeName
        if instruction.distance <= thresholds.approachDistance, announcedApproachFor != approachKey {
            announcedApproachFor = approachKey
            lastSpeechTime = now
            return .approaching(instruction)
        }

        if now - lastSpeech >= thresholds.progressReminderInterval {
            lastSpeechTime = now
            return .progress(instruction)
        }
        return nil
    }

    private mutating func warningIfDue(_ cue: GuidanceCue, now: TimeInterval) -> GuidanceCue? {
        guard now - lastWarningTime >= thresholds.offRouteRepeatInterval else { return nil }
        lastWarningTime = now
        lastSpeechTime = now
        return cue
    }
}
