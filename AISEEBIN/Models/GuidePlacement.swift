import Foundation
import simd

/// Where an on-screen guide character stands: on the floor, a little way ahead
/// of the visitor along the route (NUS Open House Guide's SoCat).
///
/// Pure geometry in the graph frame: `x`/`z` on the floor plan, `y` the floor
/// height. The caller turns it into a scene position.
enum GuidePlacement {

    /// One stop on the remaining route.
    struct Stop: Equatable {
        var planar: SIMD2<Float>
        /// Floor height under the node (world frame), if known.
        var floorY: Float?
        /// The guide waits here rather than walking on (the lift door before a
        /// lift ride: it cannot follow the visitor's camera through the shaft).
        var holdHere = false
    }

    struct Result: Equatable {
        /// Floor position (x, floor height, z).
        var position: SIMD3<Float>
        /// Planar direction of travel at that point (unit length, or zero).
        var facing: SIMD2<Float>
        /// True when the guide stopped short of `lookAhead`: at a hold point or the end.
        var waiting: Bool
    }

    /// Walks `lookAhead` metres (on the floor plan) from the visitor along
    /// `stops`, the remaining route starting with the node they are heading to.
    /// Floor height is interpolated along each leg, so the guide climbs stairs.
    static func place(from user: SIMD2<Float>, userFloorY: Float, stops: [Stop], lookAhead: Float) -> Result? {
        guard let first = stops.first else { return nil }
        var point = user
        var pointY = userFloorY
        var remaining = lookAhead
        var facing = SIMD2<Float>(0, 0)
        for stop in [first] + stops.dropFirst() {
            let stopY = stop.floorY ?? pointY
            let leg = stop.planar - point
            let length = simd_length(leg)
            if length > .ulpOfOne { facing = leg / length }
            if length >= remaining {
                let t = length > .ulpOfOne ? remaining / length : 1
                let p = point + leg * t
                return Result(position: SIMD3(p.x, pointY + (stopY - pointY) * t, p.y), facing: facing, waiting: false)
            }
            remaining -= length
            point = stop.planar
            pointY = stopY
            if stop.holdHere { break }
        }
        return Result(position: SIMD3(point.x, pointY, point.y), facing: facing, waiting: true)
    }
}
