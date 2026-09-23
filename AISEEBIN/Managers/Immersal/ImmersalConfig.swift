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

    /// Numeric map ids from the Developer Portal, in the order they should be
    /// offered to `/localizeb64` (max 8).
    static var mapIDs: [Int] {
        get { (UserDefaults.standard.string(forKey: mapIDsKey) ?? "").immersalMapIDs }
        set { UserDefaults.standard.set(newValue.map(String.init).joined(separator: ","), forKey: mapIDsKey) }
    }

    static var mapIDsText: String {
        get { UserDefaults.standard.string(forKey: mapIDsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: mapIDsKey) }
    }

    static var isConfigured: Bool { !token.isEmpty && !mapIDs.isEmpty }

    /// What is still missing, worded for the screen that asks for it.
    static var missingCredentialsHint: String {
        hasBundledToken ? "Enter the Immersal map ids below." : "Enter the Immersal token and map ids below."
    }
}

extension String {
    var immersalMapIDs: [Int] {
        split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }
    }
}
