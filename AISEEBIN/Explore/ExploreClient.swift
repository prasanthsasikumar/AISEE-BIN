import Foundation

/// Where the Explore proxy lives and how the app identifies itself to it.
enum ExploreConfig {
    static let baseURL = URL(string: "https://aiseebin.flowsxr.com/explore")!
    /// `ExploreToken` in Info.plist, filled from the `EXPLORE_TOKEN` build setting.
    static var token: String { Bundle.main.object(forInfoDictionaryKey: "ExploreToken") as? String ?? "" }
    /// Anonymous, per install; only used for the proxy's rate limit and logs.
    static var installID: String {
        let key = "explore.installID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

enum ExploreClientError: LocalizedError {
    case http(Int)
    case timeout
    var errorDescription: String? {
        switch self {
        case .http(let code): return "The guide is unavailable (\(code))."
        case .timeout: return "The guide took too long to answer."
        }
    }
}

/// Talks to the Explore proxy (server/explore): questions stream back as text,
/// a spoken time request comes back as a `TourRequest`.
final class ExploreClient {
    static let firstByteTimeout: TimeInterval = 10

    private let session: URLSession
    /// Where `explore.ask` / `explore.plan` go; tests inject a fake.
    private let usage: UsageLogging

    init(session: URLSession = .shared, usage: UsageLogging = UsageLog.shared) {
        self.session = session
        self.usage = usage
    }

    func ask(question: String, jpeg: Data?, mapSlug: String, places: [AskPlace],
             venueInfo: String?, history: [AskTurn],
             audience: String = "sighted", camera: String = "phone",
             venue: String? = nil) -> AsyncThrowingStream<String, Error> {
        struct Body: Encodable {
            let question: String
            let imageJPEGBase64: String?
            let mapSlug: String
            let places: [AskPlace]
            let venueInfo: String?
            let history: [AskTurn]
            /// Who is asking ("sighted" / "nonsighted"), through which camera
            /// ("phone" / "glasses"), and the map's display name.
            let audience: String
            let camera: String
            let venue: String?
        }
        let body = Body(question: question, imageJPEGBase64: jpeg?.base64EncodedString(), mapSlug: mapSlug,
                        places: places, venueInfo: venueInfo, history: history,
                        audience: audience, camera: camera, venue: venue)
        let request = makeRequest(path: "ask", body: body)
        let session = self.session
        let usage = self.usage
        let hadImage = jpeg != nil
        let started = Date()
        return AsyncThrowingStream { continuation in
            let task = Task {
                // `explore.ask` once the stream ends either way; never the image itself.
                var answer = ""
                func logAsk(_ error: Error?) {
                    usage.log("explore.ask", ["question": .string(question), "answer": .string(answer),
                                              "had_image": .bool(hadImage), "audience": .string(audience),
                                              "camera": .string(camera), "ms": .number(UsageRound.ms(since: started)),
                                              "ok": .bool(error == nil),
                                              "error": error.map { .string($0.localizedDescription) } ?? .null])
                }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw ExploreClientError.http(status) }
                    var pending = Data()
                    for try await byte in bytes {
                        pending.append(byte)
                        // Hand over whole UTF-8 characters only.
                        if let text = String(data: pending, encoding: .utf8) {
                            answer += text
                            continuation.yield(text)
                            pending.removeAll(keepingCapacity: true)
                        }
                    }
                    logAsk(nil)
                    continuation.finish()
                } catch {
                    logAsk(error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func plan(utterance: String, exhibits: [NavigationPOI]) async throws -> TourRequest {
        struct Exhibit: Encodable { let id, name: String; let tags: [String] }
        struct Body: Encodable { let utterance: String; let exhibits: [Exhibit] }
        struct Reply: Decodable { let minutes: Double; let interests: [String]; let mustSee: [String] }
        let request = makeRequest(path: "plan", body: Body(utterance: utterance, exhibits: exhibits.map {
            Exhibit(id: $0.id, name: $0.name, tags: $0.tags)
        }))
        let started = Date()
        func logPlan(_ reply: Reply?, _ error: Error?) {
            usage.log("explore.plan", ["utterance": .string(utterance),
                                       "minutes": reply.map { .number($0.minutes) } ?? .null,
                                       "interests": reply.map { .array($0.interests.map { .string($0) }) } ?? .null,
                                       "must_see": reply.map { .array($0.mustSee.map { .string($0) }) } ?? .null,
                                       "ms": .number(UsageRound.ms(since: started)), "ok": .bool(error == nil),
                                       "error": error.map { .string($0.localizedDescription) } ?? .null])
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw ExploreClientError.http(status) }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            logPlan(reply, nil)
            return TourRequest(minutes: reply.minutes, interests: reply.interests, mustSee: reply.mustSee)
        } catch {
            logPlan(nil, error)
            throw error
        }
    }

    private func makeRequest(path: String, body: some Encodable) -> URLRequest {
        var request = URLRequest(url: ExploreConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.firstByteTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ExploreConfig.token, forHTTPHeaderField: "X-Explore-Token")
        request.setValue(ExploreConfig.installID, forHTTPHeaderField: "X-Install-Id")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }
}
