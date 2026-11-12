import CoreVideo
import Foundation

/// Where the picture for a question comes from.
enum AskPicture {
    enum Source: String, Equatable { case glasses, phone }

    /// The glasses' camera when they are what positions the visitor (the phone
    /// is then in a pocket or on a lanyard); otherwise the phone's.
    static func source(positioning: PositioningSource, glassesConnected: Bool) -> Source {
        positioning != .phone && glassesConnected ? .glasses : .phone
    }

    /// A glasses frame older than this is not what the visitor is facing any more.
    static let maxFrameAge: TimeInterval = 3

    /// The JPEG to send. With the glasses as the source and no recent frame
    /// (none yet, or the camera has paused), the question goes without a
    /// picture: a pocketed phone would show nothing, and an old frame would be
    /// described as if it were in front of the visitor now.
    static func jpeg(source: Source, glassesFrame: CVPixelBuffer?, frameAge: TimeInterval, phone: () -> Data?) -> Data? {
        switch source {
        case .glasses:
            guard frameAge <= maxFrameAge else { return nil }
            return glassesFrame.flatMap { FrameGrabber.jpeg(from: $0) }
        case .phone: return phone()
        }
    }
}

/// Sends one question to the guide and speaks the answer sentence by sentence
/// as it streams. Shared by Explore (sighted visitors) and Navigate (blind and
/// low-vision visitors); it keeps the recent turns so follow-ups make sense.
@MainActor
final class AskService {
    static let failureText = "Sorry, I couldn't answer that just now."

    /// Everything about the moment of asking except the words.
    struct Context {
        var jpeg: Data?
        var mapSlug: String
        var places: [AskPlace]
        var venueInfo: String?
        /// "sighted" or "nonsighted".
        var audience: String
        /// "phone" or "glasses".
        var camera: String
        /// The map's display name.
        var venue: String?
    }

    enum Update: Equatable {
        case thinking
        case answering(text: String)
        case finished(answer: String)
        case failed
    }

    typealias Asker = (_ question: String, _ context: Context, _ history: [AskTurn]) -> AsyncThrowingStream<String, Error>

    private let asker: Asker
    private let speak: (_ text: String, _ interrupt: Bool) -> Void
    private var history = AskHistory()
    private var task: Task<Void, Never>?

    var isAnswering: Bool { task != nil }

    init(asker: @escaping Asker, speak: @escaping (_ text: String, _ interrupt: Bool) -> Void) {
        self.asker = asker
        self.speak = speak
    }

    convenience init(client: ExploreClient, speak: @escaping (_ text: String, _ interrupt: Bool) -> Void) {
        self.init(asker: { question, context, history in
            client.ask(question: question, jpeg: context.jpeg, mapSlug: context.mapSlug, places: context.places,
                       venueInfo: context.venueInfo, history: history,
                       audience: context.audience, camera: context.camera, venue: context.venue)
        }, speak: speak)
    }

    /// Drops an answer that is still arriving. What was already handed to the
    /// speaker is the caller's to stop.
    func cancel() {
        task?.cancel()
        task = nil
    }

    func ask(question: String, context: Context, onUpdate: @escaping (Update) -> Void) {
        cancel()
        onUpdate(.thinking)
        let stream = asker(question, context, history.recent(now: Date()))
        task = Task { [weak self] in
            var answer = ""
            var unspoken = ""
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled else { return }
                    answer += chunk
                    unspoken += chunk
                    onUpdate(.answering(text: answer))
                    let (ready, rest) = ExploreViewModel.splitSentences(unspoken)
                    if !ready.isEmpty { self.speak(ready, false) }
                    unspoken = rest
                }
                guard let self, !Task.isCancelled else { return }
                let tail = unspoken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { self.speak(tail, false) }
                if answer.isEmpty { throw ExploreClientError.timeout }
                self.history.add(q: question, a: answer, at: Date())
                self.task = nil
                onUpdate(.finished(answer: answer))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.task = nil
                if answer.isEmpty {
                    // By now the visitor has walked on: never cut off a cue to apologise.
                    self.speak(Self.failureText, false)
                    onUpdate(.failed)
                } else {
                    // Cut off part-way: what was said stands.
                    onUpdate(.finished(answer: answer))
                }
            }
        }
    }
}
