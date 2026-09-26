import Foundation

/// Immersal map binaries on disk, one `<id>.bytes` per map id, so the native
/// plugin can localize with no network. Filled whenever the app is online and
/// a map names Immersal ids; read by `ImmersalLocalizerFactory` at every
/// positioning start.
struct ImmersalMapCache {

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static let endpoint = URL(string: "https://api.immersal.com/map")!

    /// Immersal answers a refused download with a small JSON body and, at
    /// times, HTTP 200. A real map is never this small.
    static let minimumMapBytes = 1024

    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("immersal-maps", isDirectory: true)) {
        self.directory = directory
    }

    func url(for id: Int) -> URL { directory.appendingPathComponent("\(id).bytes") }

    func contains(_ id: Int) -> Bool { FileManager.default.fileExists(atPath: url(for: id).path) }

    func data(for id: Int) -> Data? { try? Data(contentsOf: url(for: id)) }

    func missing(from ids: [Int]) -> [Int] { ids.filter { !contains($0) } }

    func remove(_ id: Int) { try? FileManager.default.removeItem(at: url(for: id)) }

    /// Deletes every cached map not in `ids`.
    func prune(keeping ids: [Int]) {
        let keep = Set(ids.map { "\($0).bytes" })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".bytes") && !keep.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Downloads each of `ids` with `token`, one after another, reporting the
    /// fraction of ids done. Throws on the first failure; maps already written
    /// stay.
    func fetch(_ ids: [Int], token: String, session: URLSession = .shared,
               progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, id) in ids.enumerated() {
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            // Order matters to Immersal: `id` before `token` answers "not found".
            components.queryItems = [URLQueryItem(name: "token", value: token),
                                     URLQueryItem(name: "id", value: "\(id)")]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 120
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            guard status == 200 else { throw Failure(message: "map \(id): http \(status)") }
            if data.count < Self.minimumMapBytes {
                let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw Failure(message: "map \(id): \(reason ?? "empty response")")
            }
            // A captive portal or proxy page is a 200 too, and well over 1 KB.
            let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let first = data.first ?? 0
            if type.hasPrefix("text/") || type.hasPrefix("application/json") || first == UInt8(ascii: "<") || first == UInt8(ascii: "{") {
                throw Failure(message: "map \(id): not a map (\(type.isEmpty ? "starts with '\(Character(UnicodeScalar(first)))'" : type))")
            }
            try data.write(to: url(for: id), options: [.atomic])
            let fraction = Double(index + 1) / Double(ids.count)
            await progress(fraction)
        }
    }
}
