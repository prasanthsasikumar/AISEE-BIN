import Foundation

/// One `ab_sessions` row. Field names are the column names.
struct SessionHeader: Codable, Equatable, Sendable {
    var session_id: UUID
    var install_id: String
    var app: String                 // aiseebin | nus-open-house
    var platform: String
    var device: String
    var os_version: String
    var app_version: String
    var build_config: String        // debug | release
    var simulator: Bool
    var staff: Bool
    var started_at: Date
}

/// One `ab_events` row. `t` is ISO 8601 UTC with milliseconds.
struct QueuedEvent: Codable, Equatable, Sendable {
    var session_id: UUID
    var seq: Int
    var t: String
    var type: String
    var data: [String: UsageValue]
}

protocol UsageUploading: Sendable {
    func upload(sessions: [SessionHeader], events: [QueuedEvent]) async throws
}

/// Posts headers, then events, to Supabase. Both tables are insert-only for the
/// publishable key, so a retried batch relies on `on_conflict` plus
/// `ignore-duplicates` (ON CONFLICT DO NOTHING) to drop rows already stored.
struct UsageUploader: UsageUploading {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func upload(sessions: [SessionHeader], events: [QueuedEvent]) async throws {
        if !sessions.isEmpty { try await post(sessions, table: "ab_sessions", conflict: "session_id") }
        if !events.isEmpty { try await post(events, table: "ab_events", conflict: "session_id,seq") }
    }

    private func post<T: Encodable>(_ rows: [T], table: String, conflict: String) async throws {
        var components = URLComponents(url: ServerConfig.supabaseURL.appendingPathComponent("rest/v1/\(table)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: conflict)]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue(ServerConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(ServerConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(UsageLog.timestamp(date))
        }
        req.httpBody = try encoder.encode(rows)
        let (body, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MapSyncError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }
}
