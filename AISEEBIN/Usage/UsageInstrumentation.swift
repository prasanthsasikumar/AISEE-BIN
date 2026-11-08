import Foundation

extension UsageLogging {
    /// `settings.changed` for a user-changeable setting. A secret (a token) logs
    /// only whether it is "set" or "empty", never its value.
    func logSetting(_ key: String, old: String, new: String, secret: Bool = false) {
        guard old != new else { return }
        func shown(_ v: String) -> String { secret ? (v.isEmpty ? "empty" : "set") : v }
        log("settings.changed", ["key": .string(key), "old": .string(shown(old)), "new": .string(shown(new))])
    }
}

extension UsageLogging {
    /// `loc.attempt`: one localization request, whether or not it fixed.
    /// `source` is the positioning mode ("phone" | "lanyard") for the phone
    /// camera and "glasses" for the glasses camera. `ok` means Immersal returned
    /// a usable pose; `accepted` whether it then moved the visitor; `jump`
    /// (metres) is nil when there was nothing to jump from.
    func logLocAttempt(source: String, localizer: String, result: ImmersalLocalizeResult, ok: Bool,
                       jump: Float?, accepted: Bool) {
        log("loc.attempt", ["source": .string(source), "localizer": .string(localizer), "ok": .bool(ok),
                            "error": ok ? .null : .string(result.success ? "malformed pose" : result.error),
                            "map_id": result.mapID.map { .number(Double($0)) } ?? .null,
                            "ms": .number((result.latency * 1000).rounded()),
                            "bytes": .number(Double(result.requestBytes)),
                            "jump_m": jump.map { .number(UsageRound.cm(Double($0))) } ?? .null,
                            "accepted": .bool(accepted)])
    }

    /// `error`: a failure the app already showed or said to the user.
    func logError(_ place: String, _ error: Error) { logError(place, error.localizedDescription) }
    func logError(_ place: String, _ message: String) {
        log("error", ["where": .string(place), "message": .string(message)])
    }
}

/// Rounding for payload numbers, so events stay short.
enum UsageRound {
    static func cm(_ metres: Double) -> Double { (metres * 100).rounded() / 100 }
    static func tenths(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }
    static func ms(since start: Date) -> Double { (Date().timeIntervalSince(start) * 1000).rounded() }
}
