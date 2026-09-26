import Foundation
import Observation

/// Fills `ImmersalMapCache` from the app: once per id per launch, one download
/// at a time, with a one-line state for the status screens.
///
/// "Once per launch" is the guard against a loop: a cached file the plugin
/// refuses is deleted by `ImmersalLocalizerFactory`, and without this memory
/// the next positioning start would download it again, be refused again, and
/// restart forever. A refused map waits for the next launch, when the file
/// on the server may have changed.
@MainActor
@Observable
final class ImmersalMapDownloader {

    /// `"on device"`, `"downloading 2 maps"`, `"no token"`, `"cloud (map 5: auth)"`,
    /// `"cloud (map 5 refused this launch)"`, or `nil` before anything ran.
    private(set) var state: String?

    @ObservationIgnored let cache: ImmersalMapCache
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var attempted: Set<Int> = []
    /// The running download, tagged so whichever waiter wakes first can clear
    /// it without clobbering a newer one.
    @ObservationIgnored private var inFlight: (id: UUID, task: Task<Bool, Never>)?

    init(cache: ImmersalMapCache = ImmersalMapCache(), session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    /// Makes sure every id in `ids` is cached, downloading what is missing
    /// and not yet tried this launch. Returns whether all of them are cached
    /// now. Concurrent callers share the running download.
    func ensure(ids: [Int], token: String) async -> Bool {
        if let current = inFlight {
            // Wait for it, then fall through to the checks below: the files it
            // wrote are on disk, and the ids it tried are in `attempted`.
            _ = await current.task.value
            if inFlight?.id == current.id { inFlight = nil }
        }
        let missing = cache.missing(from: ids)
        guard !missing.isEmpty else { state = "on device"; return true }
        let refused = missing.filter { attempted.contains($0) }
        guard refused.isEmpty else {
            state = "cloud (map \(refused.map(String.init).joined(separator: ", ")) refused this launch)"
            return false
        }
        guard !token.isEmpty else { state = "no token"; return false }
        state = "downloading \(missing.count) map\(missing.count == 1 ? "" : "s")"
        attempted.formUnion(missing)
        let task = Task<Bool, Never> { [cache, session] in
            do {
                try await cache.fetch(missing, token: token, session: session)
                return true
            } catch {
                DiagnosticsLog.write("immersal map fetch failed: \(error.localizedDescription)")
                self.state = "cloud (\(error.localizedDescription))"
                return false
            }
        }
        let id = UUID()
        inFlight = (id, task)
        let ok = await task.value
        if inFlight?.id == id { inFlight = nil }
        if ok {
            cache.prune(keeping: ids)
            state = "on device"
            DiagnosticsLog.write("immersal maps cached: \(ids)")
        }
        return ok
    }
}
