import Foundation
import Observation
import simd

/// Field-test state that must survive the sheet being closed: marks not yet
/// published (and the map version they were taken on), the last scan-link
/// result, and the checks done so far this session.
@MainActor
@Observable
final class FieldTestSession {
    /// POI id → measured map position, not yet published.
    var marks: [String: SIMD2<Float>] = [:]
    /// The map version the marks were taken on. Marks are map positions under
    /// that version's scan placements, so they are dropped if it changes.
    var marksVersion: Int?
    var linkResult: [Int: ScanLinkSolver.Link] = [:]
    /// POI id → one-line result of the latest check there.
    var checks: [String: String] = [:]
}
