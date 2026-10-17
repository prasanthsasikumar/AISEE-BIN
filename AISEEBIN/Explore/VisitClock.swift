import Foundation

/// Keeps time on a visit: minutes left, how far behind plan, and which stop to
/// offer to skip when running late. The offer is only ever an offer.
struct VisitClock {
    /// Behind by more than this many minutes → offer to skip a stop.
    static let lateThreshold: Double = 3

    let plan: TourPlan
    /// Planned arrival minute at each stop, then at the end (`TourPlanner.schedule`).
    let schedule: [Double]
    let startedAt: Date
    private var arrivals: [Int: Date] = [:]

    init(plan: TourPlan, schedule: [Double], startedAt: Date) {
        self.plan = plan
        self.schedule = schedule
        self.startedAt = startedAt
    }

    mutating func arrived(at stopIndex: Int, now: Date) {
        arrivals[stopIndex] = now
    }

    func minutesLeft(budget: Double, now: Date) -> Double {
        budget - elapsed(now)
    }

    /// Minutes behind plan: late at the last stop reached, or overdue for the next one.
    func behindBy(now: Date, nextIndex: Int) -> Double {
        var behind: Double = 0
        if let last = arrivals.keys.filter({ $0 < nextIndex }).max(), last < schedule.count, let at = arrivals[last] {
            behind = max(behind, elapsed(at) - schedule[last])
        }
        if nextIndex < schedule.count {
            behind = max(behind, elapsed(now) - schedule[nextIndex])
        }
        return max(0, behind)
    }

    /// The id of the lowest-value stop still ahead, once more than 3 minutes behind.
    func lateOffer(map: NavigationMap, now: Date, nextIndex: Int) -> String? {
        guard nextIndex < plan.stopIDs.count, behindBy(now: now, nextIndex: nextIndex) > Self.lateThreshold else { return nil }
        let byID = Dictionary(map.pois.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remaining = plan.stopIDs[nextIndex...]
        // Highest highlight number = least important; among equals, the last one.
        return remaining.reversed().max { (byID[$0]?.highlightLevel ?? 2) < (byID[$1]?.highlightLevel ?? 2) }
    }

    private func elapsed(_ date: Date) -> Double { date.timeIntervalSince(startedAt) / 60 }
}
