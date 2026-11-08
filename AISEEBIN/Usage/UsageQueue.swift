import Foundation

/// Lines waiting to be uploaded, one JSON object per line in `queue.jsonl`.
/// Survives restarts: a line leaves the file only after its upload succeeded.
/// Not thread-safe on its own; `UsageLog` drives it from one serial queue.
struct UsageQueue {
    let directory: URL
    var file: URL { directory.appendingPathComponent("queue.jsonl") }

    init(directory: URL) { self.directory = directory }

    /// Application Support/usage/
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("usage", isDirectory: true)
    }

    func append(_ line: Data) throws {
        var line = line
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try line.write(to: file, options: .atomic)
        }
    }

    /// The oldest `max` lines, without removing them.
    func peekBatch(max: Int) -> [Data] {
        Array(lines().prefix(max))
    }

    /// Removes the oldest `count` lines (after they were uploaded).
    func drop(count: Int) throws {
        let rest = lines().dropFirst(count)
        if rest.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        var data = Data()
        for line in rest { data.append(line); data.append(0x0A) }
        try data.write(to: file, options: .atomic)
    }

    private func lines() -> [Data] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }
}
