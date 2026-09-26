import Foundation

/// Picks the localizer for a positioning start: the native plugin when it is
/// available and every map the alignment names is cached and loads; the
/// cloud otherwise. The reason is logged, because "why is it slow / why did
/// it stop offline" is the first field question.
enum ImmersalLocalizerFactory {

    struct Choice: Sendable {
        let localizer: any ImmersalLocalizer
        let reason: String
    }

    /// `make`, off the main actor: loading a map decompresses and indexes it,
    /// hundreds of milliseconds on a phone, and waits for any solve in flight.
    static func select(mapIDs: [Int], token: String, cache: ImmersalMapCache) async -> Choice {
        await Task.detached(priority: .userInitiated) {
            make(mapIDs: mapIDs, token: token, cache: cache)
        }.value
    }

    static func make(mapIDs: [Int], token: String, cache: ImmersalMapCache,
                     native: ImmersalNative = .shared,
                     nativeAvailable: Bool = ImmersalNative.isAvailable) -> Choice {
        let choice = choose(mapIDs: mapIDs, token: token, cache: cache,
                            native: native, nativeAvailable: nativeAvailable)
        DiagnosticsLog.write("immersal localizer: \(choice.localizer.name) (\(choice.reason)) maps=\(mapIDs)")
        return choice
    }

    private static func choose(mapIDs: [Int], token: String, cache: ImmersalMapCache,
                               native: ImmersalNative, nativeAvailable: Bool) -> Choice {
        let cloud = CloudImmersalLocalizer(token: token, mapIDs: mapIDs)
        guard nativeAvailable else {
            return Choice(localizer: cloud, reason: "plugin unavailable on this build")
        }
        let missing = cache.missing(from: mapIDs)
        guard missing.isEmpty else {
            return Choice(localizer: cloud, reason: "map \(missing.map(String.init).joined(separator: ", ")) not cached")
        }
        // Maps from a previous start that this map does not name are freed,
        // so a stale map never answers for the current space.
        for id in native.loadedMapIDs where !mapIDs.contains(id) { native.unload(mapID: id) }
        for id in mapIDs where !native.loadedMapIDs.contains(id) {
            guard let data = cache.data(for: id), native.load(mapID: id, data: data) else {
                cache.remove(id)
                return Choice(localizer: cloud, reason: "map \(id) load failed")
            }
        }
        return Choice(localizer: NativeImmersalLocalizer(native: native), reason: "maps loaded")
    }
}
