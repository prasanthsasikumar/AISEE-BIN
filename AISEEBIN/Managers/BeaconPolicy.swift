import Foundation

/// Which side of the walker the route lies on.
enum BeaconSide: Equatable {
    case left, right
}

/// What the beacon should sound like right now.
enum BeaconCue: Equatable {
    case silent
    case onCourse
    /// `pan` runs from -1 (hard left) to 1 (hard right).
    case offCourse(side: BeaconSide, pan: Float)
}

/// Decides the beacon cue from the bearing to the aim point. Pure; the only
/// state is the hysteresis, so the cue cannot flicker at the boundary.
///
/// Two states rather than a continuous slide: a walker learns "high tick =
/// fine, low pattern = turn" in a minute, and the pattern itself says which
/// way (two short = left, one long = right, like the haptics).
struct BeaconPolicy: Equatable {
    /// Off course once the bearing to the aim point exceeds this.
    var offCourseAngle: Float = 25 * .pi / 180
    /// Back on course once the bearing is within this.
    var onCourseAngle: Float = 15 * .pi / 180
    /// Bearing at which the pan reaches full left or right.
    var fullPanAngle: Float = .pi / 2

    private(set) var isOffCourse = false

    mutating func reset() { isOffCourse = false }

    /// `bearing` is the signed angle from the heading to the aim point as
    /// `NavigationGeometry.relativeBearing` gives it: positive = the route is
    /// to the right. `nil` when there is no aim point (arrived).
    mutating func evaluate(bearing: Float?, trackingReliable: Bool, navigating: Bool) -> BeaconCue {
        guard navigating, trackingReliable, let bearing else { return .silent }
        let magnitude = abs(bearing)
        if isOffCourse {
            if magnitude <= onCourseAngle { isOffCourse = false }
        } else if magnitude > offCourseAngle {
            isOffCourse = true
        }
        guard isOffCourse else { return .onCourse }
        let pan = max(-1, min(1, bearing / fullPanAngle))
        return .offCourse(side: bearing < 0 ? .left : .right, pan: pan)
    }
}
