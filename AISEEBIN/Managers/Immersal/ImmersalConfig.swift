import Foundation

/// Where the Immersal credentials and map ids live between launches.
///
/// `UserDefaults`, entered once in the probe or glasses screens. Deliberately
/// **not** a file in the repo: a developer token in source control is a token
/// that leaks. Nothing here is committed, so there is no secret to scrub. The
/// keys keep their original `probe.` prefix so testers keep their setup.
enum ImmersalConfig {
    private static let tokenKey = "probe.immersal.token"
    private static let mapIDsKey = "probe.immersal.mapIds"

    static var token: String {
        get { UserDefaults.standard.string(forKey: tokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
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
}

extension String {
    var immersalMapIDs: [Int] {
        split(whereSeparator: { ", ".contains($0) }).compactMap { Int($0) }
    }
}
