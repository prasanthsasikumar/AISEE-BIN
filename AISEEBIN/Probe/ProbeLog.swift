#if DEBUG
import ARKit
import Foundation
import simd

// THROWAWAY — see ImmersalPose.swift.

/// One line of the walk log.
///
/// A single flat schema with an `event` column, rather than three files to join
/// later. Everything Immersal returned is stored raw (see `ImmersalRawPose`), and
/// the ARKit pose is stored as position plus quaternion so a trajectory can be
/// reconstructed exactly.
struct ProbeLogRow {
    enum Event: String {
        /// Periodic ARKit pose sample.
        case frame
        /// A `/localizeb64` attempt — successful or not.
        case localize
        /// "I am physically standing at this place." Ground truth.
        case stamp
        /// A protocol marker: stepped outside, covered the lens, and so on.
        case marker
    }

    var event: Event
    /// Seconds since the log was opened. The join key between systems.
    var elapsed: TimeInterval
    var arPosition: SIMD3<Float>? = nil
    var arOrientation: simd_quatf? = nil
    var arTrackingState: String? = nil
    var arMappingStatus: String? = nil
    var arFeaturePoints: Int? = nil
    var immersalSuccess: Bool? = nil
    var immersalError: String? = nil
    var immersalMapID: Int? = nil
    var immersalPose: ImmersalRawPose? = nil
    var immersalLatency: TimeInterval? = nil
    var immersalRequestBytes: Int? = nil
    /// Metres of disagreement with ARKit odometry since the previous fix.
    var odometryDisagreement: Float? = nil
    /// `NavigationPOI.id` for a `stamp`.
    var placeID: String? = nil
    var note: String? = nil
}

/// Appends rows to a CSV in Documents.
///
/// CSV because the analysis is a short script and a spreadsheet is a useful
/// fallback if the script is never written. Flushed on every row: a crash or a
/// flat battery mid-walk must not cost the whole session.
final class ProbeLog {

    static let columns = [
        "event", "elapsed_s",
        "ar_x", "ar_y", "ar_z", "ar_qx", "ar_qy", "ar_qz", "ar_qw",
        "ar_tracking", "ar_mapping", "ar_features",
        "imm_success", "imm_error", "imm_map",
        "imm_px", "imm_py", "imm_pz",
        "imm_r00", "imm_r01", "imm_r02",
        "imm_r10", "imm_r11", "imm_r12",
        "imm_r20", "imm_r21", "imm_r22",
        "imm_latency_ms", "imm_bytes", "odom_disagreement_m",
        "place_id", "note",
    ]

    let url: URL
    private let handle: FileHandle
    private(set) var rowCount = 0

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
         startedAt: Date = Date()) throws {
        let stamp = ISO8601DateFormatter.probeFilename.string(from: startedAt)
        url = directory.appendingPathComponent("probe-\(stamp).csv")
        try Data().write(to: url, options: [.atomic])
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        write(line: Self.columns.joined(separator: ","))
    }

    func append(_ row: ProbeLogRow) {
        write(line: Self.line(for: row))
        rowCount += 1
    }

    func close() { try? handle.close() }

    private func write(line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    // MARK: - Formatting

    /// Six decimals on everything — millimetre resolution, which is well past
    /// anything either system can actually deliver, so formatting never becomes
    /// a source of error in the residuals.
    static func line(for row: ProbeLogRow) -> String {
        let p = row.arPosition
        let q = row.arOrientation
        let r = row.immersalPose?.r
        let fields: [String?] = [
            row.event.rawValue,
            number(row.elapsed),
            number(p?.x), number(p?.y), number(p?.z),
            number(q?.imag.x), number(q?.imag.y), number(q?.imag.z), number(q?.real),
            row.arTrackingState, row.arMappingStatus, row.arFeaturePoints.map(String.init),
            row.immersalSuccess.map { $0 ? "1" : "0" },
            row.immersalError,
            row.immersalMapID.map(String.init),
            number(row.immersalPose?.px), number(row.immersalPose?.py), number(row.immersalPose?.pz),
            number(r?[0]), number(r?[1]), number(r?[2]),
            number(r?[3]), number(r?[4]), number(r?[5]),
            number(r?[6]), number(r?[7]), number(r?[8]),
            row.immersalLatency.map { String(Int(($0 * 1000).rounded())) },
            row.immersalRequestBytes.map(String.init),
            number(row.odometryDisagreement),
            row.placeID,
            row.note,
        ]
        return fields.map { escape($0 ?? "") }.joined(separator: ",")
    }

    private static func number(_ value: Float?) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "%.6f", value)
    }

    private static func number(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "%.6f", value)
    }

    /// Immersal's error strings contain spaces ("map count") and a transport
    /// description can contain anything at all, commas included.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension ISO8601DateFormatter {
    static let probeFilename: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        formatter.timeZone = .current
        return formatter
    }()
}

extension ARCamera.TrackingState {
    /// Short, stable strings for the log — the user-facing labels in
    /// `LocalizationStatus` are for humans and may be reworded.
    var probeLabel: String {
        switch self {
        case .notAvailable: return "notAvailable"
        case .limited(let reason):
            switch reason {
            case .initializing:        return "limited.initializing"
            case .relocalizing:        return "limited.relocalizing"
            case .excessiveMotion:     return "limited.excessiveMotion"
            case .insufficientFeatures: return "limited.insufficientFeatures"
            @unknown default:          return "limited.unknown"
            }
        case .normal: return "normal"
        }
    }
}

extension ARFrame.WorldMappingStatus {
    var probeLabel: String {
        switch self {
        case .notAvailable: return "notAvailable"
        case .limited:      return "limited"
        case .extending:    return "extending"
        case .mapped:       return "mapped"
        @unknown default:   return "unknown"
        }
    }
}
#endif
