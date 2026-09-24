import Foundation

/// Where the Immersal credentials and map ids live between launches.
///
/// `UserDefaults`, entered once in the probe or glasses screens. Deliberately
/// **not** a file in the repo: a developer token in source control is a token
/// that leaks. Nothing here is committed, so there is no secret to scrub. The
/// keys keep their original `probe.` prefix so testers keep their setup.
///
/// A build can carry a default token so testers only type map ids: the
/// `ImmersalDefaultToken` Info.plist entry expands the `IMMERSAL_DEFAULT_TOKEN`
/// build setting, which the archive command passes in from a file outside the
/// repo. A token typed on the device still wins over the bundled one.
enum ImmersalConfig {
    private static let tokenKey = "probe.immersal.token"
    private static let mapIDsKey = "probe.immersal.mapIds"

    /// The token compiled into this build, or `nil` when it was built without one.
    static let bundledToken: String? = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ImmersalDefaultToken") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An unexpanded build setting means the archive was made without one.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }()

    static var hasBundledToken: Bool { bundledToken != nil }

    /// Only what was typed on this device, for the credential fields: an
    /// empty field with a "built in" placeholder says more than a row of dots.
    static var storedToken: String { UserDefaults.standard.string(forKey: tokenKey) ?? "" }

    static var token: String {
        get { resolveToken(stored: UserDefaults.standard.string(forKey: tokenKey), bundled: bundledToken) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    /// What typed and bundled tokens resolve to: the typed one when there is
    /// one, else the bundled one, else nothing.
    static func resolveToken(stored: String?, bundled: String?) -> String {
        let typed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return typed.isEmpty ? (bundled ?? "") : typed
    }

    /// The map ids a build offers when none have been typed on the device:
    /// the test space's map under the bundled token's Immersal account. Map
    /// ids are not secrets, so unlike the token this lives in source. Empty
    /// when the build should ask.
    static let defaultMapIDsText = "151658"   // "HusselIndoor", Pro account, 2026-09-24

    /// Numeric map ids from the Developer Portal, in the order they should be
    /// offered to `/localizeb64` (max 8).
    static var mapIDs: [Int] { mapIDsText.immersalMapIDs }

    /// Only what was typed on this device, for the map-id field.
    static var storedMapIDsText: String { UserDefaults.standard.string(forKey: mapIDsKey) ?? "" }

    static var mapIDsText: String {
        get { resolveMapIDsText(stored: storedMapIDsText, bundled: defaultMapIDsText) }
        set { UserDefaults.standard.set(newValue, forKey: mapIDsKey) }
    }

    /// Typed map ids win; the build's default fills in when nothing parses.
    static func resolveMapIDsText(stored: String?, bundled: String) -> String {
        let typed = stored ?? ""
        return typed.immersalMapIDs.isEmpty ? bundled : typed
    }

    static var isConfigured: Bool { !token.isEmpty && !mapIDs.isEmpty }

    /// The map ids a localizer should use: the loaded map's own, when it has
    /// an Immersal alignment, else what was typed in Settings. The typed ids
    /// are for the probe and for calibrating before any map is aligned; once
    /// a map names its Immersal map, that is the only sensible target.
    static func mapIDs(for alignment: ImmersalAlignment?) -> [Int] {
        if let ids = alignment?.mapIDs, !ids.isEmpty { return ids }
        return mapIDs
    }

    /// Immersal has just refused `token`. When that was a token typed on this
    /// device and the build carries its own, the typed one is stale — from a
    /// tester's old account, or the probe days — so drop it and let the built-in
    /// token take over on the next request. Returns whether anything changed.
    @discardableResult
    static func recoverFromRejectedToken(_ rejected: String, error: String) -> Bool {
        guard error == "auth" || error == "map count",
              let bundled = bundledToken,
              !storedToken.isEmpty, rejected != bundled else { return false }
        token = ""
        return true
    }

    /// What is still missing, worded for the screen that asks for it.
    static var missingCredentialsHint: String {
        hasBundledToken ? "Enter the Immersal map ids below." : "Enter the Immersal token and map ids below."
    }

    /// Placeholder for the map-id field: shows the default that applies when it is left empty.
    static var mapIDsPlaceholder: String {
        defaultMapIDsText.isEmpty ? "Map ids, comma separated" : "Map ids (default \(defaultMapIDsText))"
    }
}

extension String {
    var immersalMapIDs: [Int] {
        split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }
    }
}
