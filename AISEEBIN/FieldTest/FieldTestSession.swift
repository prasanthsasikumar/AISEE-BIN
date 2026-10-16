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
    /// Places added on site ("Add here"), in the order they were added, and
    /// the path between them; not yet published. They are positions under the
    /// same version as the marks, so `marksVersion` covers them too.
    var newPlaces: [NavigationPOI] = []
    var newEdges: [NavigationEdge] = []
    var hasPending: Bool { !marks.isEmpty || !newPlaces.isEmpty }
    var linkResult: [Int: ScanLinkSolver.Link] = [:]
    /// POI id → one-line result of the latest check there.
    var checks: [String: String] = [:]
}
