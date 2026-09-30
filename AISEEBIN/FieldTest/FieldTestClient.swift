import Foundation
import UIKit

/// Sends field-test results to `ab_field_results` and logs to storage, so a
/// test run on site can be read back the same day without anyone sending files.
enum FieldTestClient {
    struct Row: Encodable {
        var kind: String                // check | mark | link | log
        var platform = "ios"
        var device: String = FieldTestClient.deviceName
        var app_version: String = FieldTestClient.appVersion
        var map_slug: String?
        var map_version: Int?
        var mode: String?               // glasses | phone
        var localizer: String?
        var point_id: String?
        var point_name: String?
        var payload: [String: JSONValue]
    }

    /// Enough JSON for the payloads, without pulling in a dependency.
    enum JSONValue: Encodable {
        case number(Double), string(String), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .number(let v): try c.encode(v.isFinite ? v : 0)
            case .string(let v): try c.encode(v)
            case .bool(let v): try c.encode(v)
            case .array(let v): try c.encode(v)
            case .object(let v): try c.encode(v)
            case .null: try c.encodeNil()
            }
        }
    }

    static var deviceName: String {
        var info = utsname(); uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        return "\(UIDevice.current.name) · \(model) · iOS \(UIDevice.current.systemVersion)"
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    static func post(_ row: Row) async throws {
        var req = URLRequest(url: ServerConfig.supabaseURL.appendingPathComponent("rest/v1/ab_field_results"))
        req.httpMethod = "POST"
        req.setValue(ServerConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(ServerConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(row)
        let (body, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MapSyncError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Uploads the diagnostics log; returns its storage path.
    static func uploadLog(mapSlug: String?) async throws -> String {
        let data = (try? Data(contentsOf: DiagnosticsLog.url)) ?? Data("empty log".utf8)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let who = UIDevice.current.name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let path = "field-logs/\(stamp.prefix(10))/ios-\(who)-\(stamp).log"
        var req = URLRequest(url: ServerConfig.supabaseURL.appendingPathComponent("storage/v1/object/\(ServerConfig.bucket)/\(path)"))
        req.httpMethod = "POST"
        req.setValue(ServerConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(ServerConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        let (body, response) = try await URLSession.shared.upload(for: req, from: data)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MapSyncError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        try await post(Row(kind: "log", map_slug: mapSlug, payload: ["path": .string(path), "bytes": .number(Double(data.count))]))
        return path
    }
}
