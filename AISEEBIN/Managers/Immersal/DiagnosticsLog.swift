import Foundation

/// A plain text log in the app's Documents folder, for reading off a tester's
/// phone with `devicectl device copy from` when nobody can run `log collect`.
/// Positioning attempts go here as well as to the unified log. Kept small.
enum DiagnosticsLog {
    static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("immersal-diag.log")
    private static let maxBytes = 200_000
    private static let queue = DispatchQueue(label: "org.ahlab.aisee-bin.diag", qos: .utility)
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
            } else {
                try? Data(text.utf8).write(to: url)
            }
        }
    }
}
