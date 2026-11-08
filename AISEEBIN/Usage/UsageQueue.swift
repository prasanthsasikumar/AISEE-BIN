import Foundation

/// Lines waiting to be uploaded, one JSON object per line in `queue.jsonl`.
/// Survives restarts: a line leaves the queue only after its upload succeeded
/// (or was rejected). Not thread-safe on its own; `UsageLog` drives it from one
/// serial queue.
///
/// Draining is linear: `queue.offset` holds how many bytes at the front of the
/// file are already uploaded. Dropping lines only advances that offset; the
/// file is rewritten (compacted) only once the consumed part is more than half
/// of it, so a long backlog is copied a handful of times, not once per batch.
///
/// Crash safety: the offset only ever points at or before the first line not
/// yet uploaded. Whenever the file is replaced or removed, the offset is reset
/// first, so a crash in between re-uploads lines (the server ignores
/// duplicates) instead of skipping any.
final class UsageQueue {
    let directory: URL
    var file: URL { directory.appendingPathComponent("queue.jsonl") }
    var offsetFile: URL { directory.appendingPathComponent("queue.offset") }
    /// Called after each compaction (the file rewritten); tests count them.
    private let onCompact: (() -> Void)?

    private static let chunkSize = 64 * 1024
    private static let newline: UInt8 = 0x0A

    init(directory: URL, onCompact: (() -> Void)? = nil) {
        self.directory = directory
        self.onCompact = onCompact
    }

    /// Application Support/usage/
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("usage", isDirectory: true)
    }

    /// Appends one line. Starts on a fresh line if a crash left the last one
    /// unfinished. Throws, and leaves the queue as it was, when an existing
    /// file cannot be opened: the caller drops this one line rather than
    /// replacing the queue.
    func append(_ line: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: file.path) {
            let handle = try FileHandle(forUpdating: file)
            defer { try? handle.close() }
            var data = Data()
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1) != Data([Self.newline]) { data.append(Self.newline) }
                try handle.seekToEnd()
            }
            data.append(line)
            data.append(Self.newline)
            try handle.write(contentsOf: data)
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // An offset left from an earlier file would skip lines of this one.
            try removeIfPresent(offsetFile)
            var data = line
            data.append(Self.newline)
            try data.write(to: file, options: .atomic)
        }
    }

    /// The oldest `max` lines, without removing them. Throws on a read error.
    func peekBatch(max: Int) throws -> [Data] {
        try scan(from: try offset(), max: max, keep: true).lines
    }

    /// Removes the oldest `count` lines (after they were uploaded). Throws on
    /// a read error without touching the queue.
    func drop(count: Int) throws {
        guard count > 0 else { return }
        let start = try offset()
        let end = try scan(from: start, max: count, keep: false).end
        try advance(to: end)
    }

    /// Drops the oldest lines beyond `max`; returns how many were dropped.
    @discardableResult
    func trim(keepingLast max: Int) throws -> Int {
        let start = try offset()
        // Every line takes at least two bytes with its newline: a short
        // file cannot be over the cap, so skip counting it.
        let remaining = try fileSize() - start
        if remaining < UInt64(2 * (max + 1)) { return 0 }
        let total = try scan(from: start, max: .max, keep: false).count
        let excess = total - max
        guard excess > 0 else { return 0 }
        try drop(count: excess)
        return excess
    }

    // MARK: - Offset

    /// Bytes at the front of the file already uploaded; 0 if unknown or stale.
    private func offset() throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: offsetFile.path) else { return 0 }
        let text = try String(contentsOf: offsetFile, encoding: .utf8)
        guard let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return value <= (try fileSize()) ? value : 0
    }

    private func writeOffset(_ value: UInt64) throws {
        try Data(String(value).utf8).write(to: offsetFile, options: .atomic)
    }

    /// Marks everything before `end` as uploaded: removes the queue when it is
    /// all consumed, compacts it when more than half is, else moves the offset.
    private func advance(to end: UInt64) throws {
        let size = try fileSize()
        if end >= size {
            try removeIfPresent(offsetFile)
            try removeIfPresent(file)
        } else if end > size / 2 {
            let handle = try FileHandle(forReadingFrom: file)
            let rest: Data
            do {
                defer { try? handle.close() }
                try handle.seek(toOffset: end)
                rest = try handle.readToEnd() ?? Data()
            }
            let tmp = directory.appendingPathComponent("queue.jsonl.tmp")
            try rest.write(to: tmp, options: .atomic)
            try writeOffset(0)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
            onCompact?()
        } else {
            try writeOffset(end)
        }
    }

    // MARK: - Reading

    /// Up to `max` non-empty lines from byte `start`, and the offset just past
    /// the last one. A final line without a newline (a crash mid-append)
    /// counts as a line. `keep` false only counts.
    private func scan(from start: UInt64, max: Int, keep: Bool) throws -> (lines: [Data], count: Int, end: UInt64) {
        guard max > 0, FileManager.default.fileExists(atPath: file.path) else { return ([], 0, start) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        var lines: [Data] = []
        var count = 0
        var end = start
        var chunkStart = start
        var pending = Data()
        var pendingLength = 0
        while count < max {
            guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                if pendingLength > 0 {
                    if keep { lines.append(pending) }
                    count += 1
                    end = chunkStart
                }
                break
            }
            var lineStart = chunk.startIndex
            while count < max, let nl = chunk[lineStart...].firstIndex(of: Self.newline) {
                let length = pendingLength + (nl - lineStart)
                if length > 0 {
                    if keep { lines.append(pending + chunk[lineStart..<nl]) }
                    count += 1
                }
                pending = Data()
                pendingLength = 0
                lineStart = nl + 1
                end = chunkStart + UInt64(lineStart - chunk.startIndex)
            }
            if count < max {
                if keep { pending.append(chunk[lineStart...]) }
                pendingLength += chunk.endIndex - lineStart
            }
            chunkStart += UInt64(chunk.count)
        }
        return (lines, count, end)
    }

    private func fileSize() throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
