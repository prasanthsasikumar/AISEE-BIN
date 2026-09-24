import Foundation

/// Supabase Cloud, project `djfpemdkeguztyuerxqc` in ap-southeast-1 (see
/// ../SUPABASE.md). The publishable key is client-safe by design; Row Level
/// Security limits it to reading and appending map versions.
///
/// Moved off the self-hosted VPS (db.flowsxr.com) on 2026-09-09: that origin sat
/// 266 ms away and served one connection at ~40 KB/s, so a world map took ten
/// minutes to install. Storage here is CDN-fronted and the same map lands in
/// about four seconds. Builds shipped before this date still point at the VPS,
/// which is left running and untouched.
enum ServerConfig {
    static let supabaseURL = URL(string: "https://djfpemdkeguztyuerxqc.supabase.co")!
    static let publishableKey = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"
    static let bucket = "aiseebin-maps"
    /// Storage paths embed the version, so uploaded blobs are immutable and can be
    /// cached forever. Supabase's default is `no-cache`, which re-fetched a 30 MB
    /// world map on every install.
    static let blobCacheControl = "public, max-age=31536000, immutable"
    /// Slug used by bundles authored before maps could be named.
    static let mapSlug = "default"
    static let editorURL = URL(string: "https://aiseebin.flowsxr.com")!

    /// Turns a map name into a server slug, matching the web editor's rule
    /// (`web/app.js`): lowercased, runs of non-alphanumerics collapsed to a
    /// single dash, no leading or trailing dash. A name with nothing to slugify
    /// falls back to `mapSlug` so a map is never published unaddressable.
    static func slug(from name: String) -> String {
        let base = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return base.isEmpty ? mapSlug : base
    }
}

enum MapSource: String, Codable {
    case ios, web
}

/// One row of `ab_map_versions`.
struct RemoteMapVersion: Codable, Identifiable {
    let id: String
    let mapSlug: String
    let version: Int
    let source: MapSource
    let note: String?
    let graph: NavigationMap
    let worldmapPath: String?
    let pointcloudPath: String?
    let pointCount: Int?
    let createdAt: Date
}

/// One map on the server, as the picker lists it: the newest version of a slug.
/// Deliberately excludes `graph`, so listing every map costs one small response
/// no matter how large the maps are.
struct RemoteMapSummary: Codable, Identifiable, Equatable {
    let slug: String
    let name: String
    let version: Int
    let source: MapSource
    let pointCount: Int
    let createdAt: Date

    var id: String { slug }

    /// `map_slug` on the wire; `name` is aliased out of the graph JSON by the query.
    private enum CodingKeys: String, CodingKey {
        case slug = "mapSlug", name, version, source, pointCount, createdAt
    }
}

/// What the app currently has on disk.
struct LocalMapVersion: Codable, Equatable {
    var version: Int
    var source: MapSource
    var updatedAt: Date
    /// Which server map this bundle belongs to. Once set, publishing keeps using
    /// it, so renaming a map does not orphan its version history.
    var slug: String

    init(version: Int, source: MapSource, updatedAt: Date, slug: String = ServerConfig.mapSlug) {
        self.version = version
        self.source = source
        self.updatedAt = updatedAt
        self.slug = slug
    }

    // Records written before maps could be named have no slug on disk; they are
    // all bundles of the one hardcoded map.
    private enum CodingKeys: String, CodingKey { case version, source, updatedAt, slug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        source = try c.decode(MapSource.self, forKey: .source)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ServerConfig.mapSlug
    }
}

extension JSONDecoder {
    /// Snake-case keys and Postgres timestamps with fractional seconds.
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: string) ?? isoPlain.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }()
}

/// Progress of a download: 0…1 plus the byte counts the UI prints under the bar.
struct DownloadProgress: Equatable {
    let fraction: Double
    let receivedBytes: Int
    let totalBytes: Int

    /// "28.4 MB of 76.8 MB", or just the received size when the total is unknown.
    var bytesText: String {
        let received = ByteCountFormatter.string(fromByteCount: Int64(receivedBytes), countStyle: .file)
        guard totalBytes > 0 else { return received }
        return "\(received) of \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))"
    }
}

/// Progress of a multi-file transfer, 0…1 overall plus a human-readable stage.
struct TransferProgress: Equatable {
    let stage: String
    let fraction: Double
    /// The reserved server version, known once the number has been claimed.
    var version: Int?
    /// Bytes across the whole transfer, for "20.3 MB of 31.7 MB".
    var sentBytes: Int?
    var totalBytes: Int?

    var percent: Int { Int((fraction * 100).rounded()) }

    var bytesText: String? {
        guard let sentBytes, let totalBytes, totalBytes > 0 else { return nil }
        let sent = ByteCountFormatter.string(fromByteCount: Int64(sentBytes), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return "\(sent) of \(total)"
    }
}

/// Forwards URLSession upload byte counters to a closure on the main actor.
private final class TransferDelegate: NSObject, URLSessionTaskDelegate {
    private let onBytes: @MainActor (Int64, Int64) -> Void

    init(onBytes: @escaping @MainActor (Int64, Int64) -> Void) {
        self.onBytes = onBytes
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let handler = onBytes
        Task { @MainActor in handler(totalBytesSent, totalBytesExpectedToSend) }
    }
}

enum MapSyncError: LocalizedError {
    case http(Int, String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "Server returned \(code): \(body.prefix(200))"
        case .missingFile(let what):    return "Server version has no \(what)."
        }
    }
}

/// Uploads authored map bundles and fetches the newest version for navigation.
struct MapSyncService {

    /// Long timeouts: a world map can be tens of megabytes on greenhouse Wi-Fi.
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// `true` when the server has something the device does not.
    static func shouldDownload(remoteVersion: Int, local: LocalMapVersion?) -> Bool {
        guard let local else { return true }
        return remoteVersion > local.version
    }

    // MARK: - Read

    func latestVersion(slug: String = ServerConfig.mapSlug) async throws -> RemoteMapVersion? {
        var components = URLComponents(url: ServerConfig.supabaseURL.appendingPathComponent("rest/v1/ab_map_versions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "map_slug", value: "eq.\(slug)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "version.desc"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        let data = try await perform(request(components.url!, method: "GET"))
        return try JSONDecoder.supabase.decode([RemoteMapVersion].self, from: data).first
    }

    /// Every map on the server, newest version of each, ordered by slug.
    func availableMaps() async throws -> [RemoteMapSummary] {
        var components = URLComponents(url: ServerConfig.supabaseURL.appendingPathComponent("rest/v1/ab_map_versions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            // `name` lives inside the graph JSON; PostgREST can alias it out so the
            // heavy `graph` column never crosses the wire.
            URLQueryItem(name: "select", value: "map_slug,version,source,created_at,point_count,name:graph->>name"),
            URLQueryItem(name: "order", value: "map_slug.asc,version.desc"),
        ]
        let data = try await perform(request(components.url!, method: "GET"))
        return Self.latestPerSlug(try JSONDecoder.supabase.decode([RemoteMapSummary].self, from: data))
    }

    /// Collapses version rows to one entry per map, keeping the highest version
    /// (and therefore its name, which a rename on the web editor changes).
    /// Does not rely on the query's ordering, so a reordered response is still correct.
    static func latestPerSlug(_ rows: [RemoteMapSummary]) -> [RemoteMapSummary] {
        var newest: [String: RemoteMapSummary] = [:]
        for row in rows where row.version > (newest[row.slug]?.version ?? Int.min) {
            newest[row.slug] = row
        }
        return newest.values.sorted { $0.slug < $1.slug }
    }

    /// Bytes per Range request. Small enough that one chunk finishes well inside
    /// any gateway timeout on a slow link; large enough to keep overhead low.
    static let downloadChunkSize = 2 * 1024 * 1024
    static let downloadRetriesPerChunk = 4
    /// Range requests in flight at once. The origin caps a single connection at
    /// roughly 40 KB/s but serves about 155 KB/s spread over six, so the fan-out —
    /// not the chunk size — is what makes a 30 MB world map bearable on a 266 ms link.
    static let downloadConcurrency = 6

    /// Downloads a public object as concurrent Range requests, reassembles it in
    /// offset order, and reports 0…1 as bytes arrive.
    ///
    /// The gateway used to cut any response longer than 30 s, and mobile links
    /// drop mid-transfer anyway, so a single 30 MB GET is fragile. Chunks are
    /// retried independently; only the failed chunk is re-fetched.
    func download(path: String, progress: @escaping @MainActor (DownloadProgress) -> Void = { _ in }) async throws -> Data {
        let url = ServerConfig.supabaseURL.appendingPathComponent("storage/v1/object/public/\(ServerConfig.bucket)/\(path)")
        let session = self.session

        // The first chunk doubles as the size probe: its Content-Range names the total.
        let (firstChunk, reportedTotal) = try await Self.fetchChunkRetrying(url: url, index: 0, session: session)
        guard let total = reportedTotal, total > firstChunk.count else {
            // Either the server ignored Range (200, whole body) or it all fit in one chunk.
            await progress(DownloadProgress(fraction: 1, receivedBytes: firstChunk.count, totalBytes: firstChunk.count))
            return try Self.decoded(firstChunk, path: path)
        }

        let chunkCount = (total + Self.downloadChunkSize - 1) / Self.downloadChunkSize
        var chunks: [Int: Data] = [0: firstChunk]
        // Chunks land out of order, so progress counts bytes received, never the offset reached.
        var received = firstChunk.count
        await progress(DownloadProgress(fraction: Double(received) / Double(total),
                                        receivedBytes: received, totalBytes: total))

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var next = 1
            func fetch(_ index: Int) {
                group.addTask {
                    (index, try await Self.fetchChunkRetrying(url: url, index: index, session: session).0)
                }
            }
            while next < chunkCount && next <= Self.downloadConcurrency { fetch(next); next += 1 }

            // Each completion frees a slot, keeping the fan-out at a steady width.
            while let (index, body) = try await group.next() {
                chunks[index] = body
                received += body.count
                await progress(DownloadProgress(fraction: min(1, Double(received) / Double(total)),
                                                receivedBytes: received, totalBytes: total))
                if next < chunkCount { fetch(next); next += 1 }
            }
        }

        // Dropping each chunk as it is appended keeps the peak near one copy of the
        // object rather than two — worth caring about for a 30 MB map on a phone.
        var data = Data(capacity: total)
        for index in 0..<chunkCount {
            guard let chunk = chunks.removeValue(forKey: index) else {
                throw MapSyncError.missingFile("chunk \(index) of \(path)")
            }
            data.append(chunk)
        }
        await progress(DownloadProgress(fraction: 1, receivedBytes: data.count, totalBytes: total))
        return try Self.decoded(data, path: path)
    }

    /// Unwraps a gzipped object. Compression is carried by the `.gz` suffix on the
    /// stored path, so call sites hand the bytes straight to `MapStore` either way
    /// and maps published before compression keep working untouched.
    private static func decoded(_ data: Data, path: String) throws -> Data {
        guard GzipCodec.isCompressed(path: path) else { return data }
        return try GzipCodec.decompress(data)
    }

    /// Fetches one chunk, retrying transient failures with a widening backoff.
    private static func fetchChunkRetrying(url: URL, index: Int, session: URLSession) async throws -> (Data, Int?) {
        let start = index * downloadChunkSize
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(start + downloadChunkSize - 1)", forHTTPHeaderField: "Range")

        var lastError: Error?
        for attempt in 1...downloadRetriesPerChunk {
            do {
                return try await fetchChunk(request, session: session)
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }
        }
        throw lastError ?? MapSyncError.http(0, "download chunk \(index)")
    }

    /// Returns the chunk body and the object's total size parsed from
    /// `Content-Range`, or `nil` total when the server answered 200 (no Range).
    private static func fetchChunk(_ request: URLRequest, session: URLSession) async throws -> (Data, Int?) {
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return (body, nil) }
        switch http.statusCode {
        case 206:
            // Content-Range: bytes 0-2097151/31739511
            let header = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            let total = header.split(separator: "/").last.flatMap { Int($0) }
            return (body, total)
        case 200:
            return (body, nil)
        default:
            throw MapSyncError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Write

    /// Publishes a new version: uploads the world map and point cloud, then the row.
    /// `worldMap` is nil for a map whose graph is not in ARKit's frame (drawn in
    /// the editor on an Immersal scan): the row then carries no world map and the
    /// phone positions itself through Immersal instead.
    func upload(graph: NavigationMap,
                worldMap: Data?,
                pointCloud: Data,
                pointCount: Int,
                note: String?,
                slug: String = ServerConfig.mapSlug,
                progress: @escaping @MainActor (TransferProgress) -> Void = { _ in }) async throws -> RemoteMapVersion {
        await progress(TransferProgress(stage: "Reserving version number…", fraction: 0))
        let version = try await nextVersion(slug: slug)
        let folder = "\(slug)/v\(version)"
        let worldMapPath = "\(folder)/greenhouse.arworldmap.gz"
        let pointsPath = "\(folder)/points.f32.gz"

        // Both blobs travel gzipped. The world map only reaches about 73% of its
        // size — ARWorldMap is already dense — but on a link this slow that is still
        // half a minute, far more than the second or two spent compressing.
        await progress(TransferProgress(stage: "Compressing…", fraction: 0, version: version))
        let worldMapBody = worldMap.map { GzipCodec.compress($0) } ?? Data()
        let pointsBody = GzipCodec.compress(pointCloud)

        // Overall fraction is bytes sent over total bytes across both files, counted
        // after compression so the bar tracks what actually crosses the wire.
        let allBytes = worldMapBody.count + pointsBody.count
        let totalBytes = Double(allBytes)
        let worldMapLabel = "Uploading world map v\(version) (\(ByteCountFormatter.string(fromByteCount: Int64(worldMapBody.count), countStyle: .file)))"
        if worldMap != nil {
            try await uploadObject(worldMapBody, to: worldMapPath, contentType: "application/gzip") { sent, _ in
                progress(TransferProgress(stage: worldMapLabel, fraction: Double(sent) / totalBytes,
                                          version: version, sentBytes: Int(sent), totalBytes: allBytes))
            }
        }
        let pointsLabel = "Uploading point cloud (\(ByteCountFormatter.string(fromByteCount: Int64(pointsBody.count), countStyle: .file)))"
        try await uploadObject(pointsBody, to: pointsPath, contentType: "application/gzip") { sent, _ in
            progress(TransferProgress(stage: pointsLabel,
                                      fraction: (Double(worldMapBody.count) + Double(sent)) / totalBytes,
                                      version: version, sentBytes: worldMapBody.count + Int(sent), totalBytes: allBytes))
        }
        await progress(TransferProgress(stage: "Publishing version record…", fraction: 0.99,
                                        version: version, sentBytes: allBytes, totalBytes: allBytes))

        struct Row: Encodable {
            let map_slug: String; let version: Int; let source: String; let note: String?
            let graph: NavigationMap; let worldmap_path: String?; let pointcloud_path: String; let point_count: Int
        }
        let row = Row(map_slug: slug, version: version, source: MapSource.ios.rawValue, note: note,
                      graph: graph, worldmap_path: worldMap == nil ? nil : worldMapPath,
                      pointcloud_path: pointsPath, point_count: pointCount)

        var req = request(ServerConfig.supabaseURL.appendingPathComponent("rest/v1/ab_map_versions"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(row)
        let data = try await perform(req)
        guard let saved = try JSONDecoder.supabase.decode([RemoteMapVersion].self, from: data).first else {
            throw MapSyncError.http(200, "empty insert response")
        }
        return saved
    }

    // MARK: - Private

    private func nextVersion(slug: String) async throws -> Int {
        var req = request(ServerConfig.supabaseURL.appendingPathComponent("rest/v1/rpc/ab_next_version"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["slug": slug])
        let data = try await perform(req)
        return try JSONDecoder().decode(Int.self, from: data)
    }

    private func uploadObject(_ data: Data, to path: String, contentType: String,
                              progress: @escaping @MainActor (Int64, Int64) -> Void) async throws {
        var req = request(ServerConfig.supabaseURL.appendingPathComponent("storage/v1/object/\(ServerConfig.bucket)/\(path)"), method: "POST")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        // Paths carry their version (`<slug>/v<n>/…`), so an object never changes
        // once written and may be cached by the CDN and the client indefinitely.
        req.setValue(ServerConfig.blobCacheControl, forHTTPHeaderField: "Cache-Control")
        let delegate = TransferDelegate(onBytes: progress)
        let (body, response) = try await session.upload(for: req, from: data, delegate: delegate)
        _ = try Self.validate(body, response)
    }

    private func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(ServerConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(ServerConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (body, response) = try await session.data(for: req)
        return try Self.validate(body, response)
    }

    private static func validate(_ body: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { return body }
        guard (200..<300).contains(http.statusCode) else {
            throw MapSyncError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return body
    }
}
