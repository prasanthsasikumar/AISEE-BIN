import Foundation

/// Recorded clips for the fixed phrases the app speaks most (see `voice/`).
/// `GuidanceManager` plays a clip when the text matches one exactly, and the
/// system voice speaks everything else.
struct VoiceClips {
    private let directory: URL?
    private let files: [String: String]

    /// The clips bundled from `voice/clips`, or none if the folder is missing.
    static let bundled = VoiceClips(directory: Bundle.main.url(forResource: "clips", withExtension: nil))

    init(directory: URL?) {
        self.directory = directory
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            files = [:]
            return
        }
        files = index.clips.mapValues(\.file)
    }

    var count: Int { files.count }

    /// The clip for `text`, if one was recorded.
    func url(for text: String) -> URL? {
        guard let directory, let file = files[Self.normalise(text)] else { return nil }
        return directory.appendingPathComponent(file)
    }

    /// Must match `normalise` in voice/generate.py and VoiceClips.kt.
    static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private struct Index: Decodable {
        struct Clip: Decodable { let file: String }
        let clips: [String: Clip]
    }
}
