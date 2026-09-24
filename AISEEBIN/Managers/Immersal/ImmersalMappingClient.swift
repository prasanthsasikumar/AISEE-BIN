import Foundation

/// The mapping half of Immersal's REST API: photos into the account's
/// workspace, then a construction job that becomes a map. Same shape as
/// `ImmersalClient`, which does the localizing half.
struct ImmersalMappingClient {
    static let base = URL(string: "https://api.immersal.com")!

    let token: String
    var session: URLSession = .shared

    struct Failure: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    struct MapStatus: Equatable {
        var id: Int
        var name: String
        var status: String     // "pending", "processing", "done", "failed"
        var size: Int
    }

    /// Empties the workspace so a new scan starts from nothing.
    func clearWorkspace() async throws {
        _ = try await post("clear", ["token": token, "anchor": true])
    }

    /// Uploads one mapping photo with its camera pose and intrinsics.
    func capture(png: Data, pose: ImmersalCapturePose.Encoded,
                 fx: Float, fy: Float, ox: Float, oy: Float,
                 run: Int, index: Int, anchor: Bool) async throws {
        var body: [String: Any] = [
            "token": token, "run": run, "index": index, "anchor": anchor,
            "b64": png.base64EncodedString(),
            "fx": fx, "fy": fy, "ox": ox, "oy": oy,
            "latitude": 0.0, "longitude": 0.0, "altitude": 0.0,
        ]
        body.merge(pose.fields) { _, new in new }
        _ = try await post("captureb64", body, timeout: 120)
    }

    /// Starts construction from the workspace; returns the new map's id.
    func construct(name: String, preservePoses: Bool) async throws -> Int {
        let reply = try await post("construct", ["token": token, "name": name, "preservePoses": preservePoses])
        guard let id = reply["id"] as? Int else { throw Failure(message: "construct: no map id in reply") }
        return id
    }

    /// Every map on the account, with construction status.
    func list() async throws -> [MapStatus] {
        let reply = try await post("list", ["token": token])
        let jobs = reply["jobs"] as? [[String: Any]] ?? []
        return jobs.compactMap { j in
            guard let id = j["id"] as? Int else { return nil }
            return MapStatus(id: id, name: j["name"] as? String ?? "", status: j["status"] as? String ?? "?", size: j["size"] as? Int ?? 0)
        }
    }

    func status(of mapID: Int) async throws -> MapStatus? {
        try await list().first { $0.id == mapID }
    }

    private func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 30) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = timeout
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw Failure(message: "transport: \(error.localizedDescription)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "\(path): unreadable reply")
        }
        if let err = json["error"] as? String, err != "none" { throw Failure(message: "\(path): \(err)") }
        return json
    }
}
