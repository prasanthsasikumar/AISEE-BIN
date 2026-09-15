//
// AiSeeSequencing.swift — AiSeeGlassKit
//
// The still-photo rules from FINDINGS.md (SDK 1.6.4) as a pure function, so
// they are unit-tested without hardware. AiSeeDeviceCoordinator executes the
// plan; nothing else decides when the mic or camera opens.
//
//   F1  mic open across snapshot() wedges the device → close mic 400 ms before,
//       settle 300 ms, reopen after.
//   F2  stills right after a livestream time out → 1 s settle after stop.
//   —   a still during a livestream is served from the latest decoded frame.
//
// Foundation only.
//

import Foundation

enum AiSeeSequencing {
    struct State: Equatable {
        var micOpen: Bool
        var streaming: Bool
        var lastStreamStop: Date?
    }

    enum Step: Equatable {
        case closeMic
        case wait(ms: Int)
        case shoot
        case reopenMic
        case serveLatestFrame
    }

    static let micCloseLeadMs = 400
    static let micSettleMs = 300
    static let postStreamSettleMs = 1000

    static func stillPhotoPlan(state: State, now: Date) -> [Step] {
        if state.streaming { return [.serveLatestFrame] }

        var plan: [Step] = []
        if let stop = state.lastStreamStop {
            let elapsedMs = Int(round(now.timeIntervalSince(stop) * 1000))
            // Clamped: a clock change can put `lastStreamStop` in the future, and
            // waiting more than the settle itself is never right.
            let remaining = min(postStreamSettleMs, postStreamSettleMs - elapsedMs)
            if remaining > 0 { plan.append(.wait(ms: remaining)) }
        }
        if state.micOpen {
            plan += [.closeMic, .wait(ms: micCloseLeadMs), .wait(ms: micSettleMs), .shoot, .reopenMic]
        } else {
            plan.append(.shoot)
        }
        return plan
    }
}
