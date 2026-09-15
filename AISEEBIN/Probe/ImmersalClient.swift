import Foundation

// THROWAWAY — see ImmersalPose.swift.

/// One `/localizeb64` round trip.
struct ImmersalLocalizeResult {
    var success: Bool
    /// `"none"` on success; otherwise Immersal's own code — `auth`, `query`,
    /// `map count`, `image` — or a transport description.
    var error: String
    /// Which map answered. Worth logging: at the indoor/outdoor transition, the
    /// *wrong* map answering is itself the finding.
    var mapID: Int?
    var pose: ImmersalRawPose?
    var latency: TimeInterval
    var requestBytes: Int
}

/// Minimal REST client for server-side localization.
///
/// Server-side on purpose: it needs no plugin, no xcframework and no build
/// changes, so the harness stays deletable. The trade-off is that it measures
/// *network-dependent* localization — which is the honest thing to measure
/// anyway, given the greenhouse Wi-Fi this app already has to cope with. Frames
/// that fail to send are queued and replayed, so a dead spot costs latency
/// numbers but not accuracy numbers.
struct ImmersalClient {

    static let endpoint = URL(string: "https://api.immersal.com/localizeb64")!

    let token: String
    let mapIDs: [Int]
    var session: URLSession = .shared

    /// `/localizeb64` caps a request at 8 maps.
    static let maxMaps = 8

    private struct Response: Decodable {
        var error: String?
        var success: Bool?
        var map: Int?
        var px: Float?
        var py: Float?
        var pz: Float?
        var r00: Float?; var r01: Float?; var r02: Float?
        var r10: Float?; var r11: Float?; var r12: Float?
        var r20: Float?; var r21: Float?; var r22: Float?

        var rawPose: ImmersalRawPose? {
            guard let px, let py, let pz,
                  let r00, let r01, let r02,
                  let r10, let r11, let r12,
                  let r20, let r21, let r22 else { return nil }
            return ImmersalRawPose(px: px, py: py, pz: pz,
                                   r: [r00, r01, r02, r10, r11, r12, r20, r21, r22])
        }
    }

    func localize(pngData: Data, fx: Float, fy: Float, ox: Float, oy: Float) async -> ImmersalLocalizeResult {
        let body: [String: Any] = [
            "token": token,
            "mapIds": mapIDs.prefix(Self.maxMaps).map { ["id": $0] },
            "b64": pngData.base64EncodedString(),
            "fx": fx, "fy": fy, "ox": ox, "oy": oy,
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return ImmersalLocalizeResult(success: false, error: "encode", mapID: nil,
                                          pose: nil, latency: 0, requestBytes: 0)
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 20

        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = Date().timeIntervalSince(started)

            // The body is decoded *before* the status code is consulted, because
            // Immersal reports a rejected request as HTTP 400 carrying the reason
            // that actually matters — `{"error":"auth"}` for a bad token,
            // `"map count"` for more than eight maps, `"query"` for a malformed
            // body. Checking the status first would log every one of those as
            // "http 400" and send someone back to the greenhouse to find out why.
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                let status = (response as? HTTPURLResponse)?.statusCode
                return ImmersalLocalizeResult(success: false,
                                              error: status.map { "http \($0), undecodable body" } ?? "decode",
                                              mapID: nil, pose: nil, latency: latency,
                                              requestBytes: payload.count)
            }
            // A pose is only trusted when Immersal says so *and* the numbers parse.
            let pose = decoded.rawPose
            let ok = (decoded.success ?? false) && decoded.error == "none" && pose != nil
            return ImmersalLocalizeResult(success: ok,
                                          error: decoded.error ?? (ok ? "none" : "missing error field"),
                                          mapID: decoded.map, pose: pose,
                                          latency: latency, requestBytes: payload.count)
        } catch {
            // Transport failure. The caller queues the frame for replay.
            return ImmersalLocalizeResult(success: false, error: "transport: \(error.localizedDescription)",
                                          mapID: nil, pose: nil,
                                          latency: Date().timeIntervalSince(started),
                                          requestBytes: payload.count)
        }
    }

    /// Distinguishes "the network failed, retry later" from "Immersal answered no".
    static func isTransportFailure(_ error: String) -> Bool { error.hasPrefix("transport:") }
}
