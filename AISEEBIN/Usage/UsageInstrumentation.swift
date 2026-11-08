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
