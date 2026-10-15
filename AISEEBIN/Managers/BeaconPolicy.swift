import Foundation

/// Which side of the walker the route lies on.
enum BeaconSide: Equatable {
    case left, right
}

/// The audible pattern of a cue: what decides whether the loop restarts.
/// Pan is deliberately not part of it, since it changes with every frame.
enum BeaconPattern: Equatable {
    case silent, onCourse, offCourseLeft, offCourseRight
}

/// What the beacon should sound like right now.
enum BeaconCue: Equatable {
    case silent
    case onCourse
    /// `pan` runs from -1 (hard left) to 1 (hard right).
    case offCourse(side: BeaconSide, pan: Float)

    var pattern: BeaconPattern {
        switch self {
        case .silent: return .silent
        case .onCourse: return .onCourse
        case .offCourse(let side, _): return side == .left ? .offCourseLeft : .offCourseRight
        }
    }

    var pan: Float {
        if case .offCourse(_, let pan) = self { return pan }
        return 0
    }
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
    /// Beyond this the aim point is behind the walker and the bearing jitters
    /// across ±180°; the side already chosen is kept rather than flipping.
    var sideHoldAngle: Float = 150 * .pi / 180

    private(set) var isOffCourse = false
    private(set) var heldSide: BeaconSide?

    mutating func reset() {
        isOffCourse = false
        heldSide = nil
    }

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
        guard isOffCourse else {
            heldSide = nil
            return .onCourse
        }
        let side: BeaconSide
        if magnitude > sideHoldAngle, let held = heldSide {
            side = held
        } else {
            side = bearing < 0 ? .left : .right
        }
        heldSide = side
        let pan = max(-1, min(1, bearing / fullPanAngle))
        return .offCourse(side: side, pan: pan)
    }
}

/// Silences a beacon nobody is feeding. When poses stop arriving (ARKit
/// interrupted, the app in the background) no cue is applied, and a loop that
/// kept ticking "on course" would claim a position it no longer has.
struct BeaconWatchdog: Equatable {
    var starveAfter: TimeInterval = 1
    private var lastFed: TimeInterval?

    mutating func feed(at time: TimeInterval) { lastFed = time }

    mutating func reset() { lastFed = nil }

    func isStarved(at time: TimeInterval) -> Bool {
        guard let lastFed else { return false }
        return time - lastFed > starveAfter
    }
}
