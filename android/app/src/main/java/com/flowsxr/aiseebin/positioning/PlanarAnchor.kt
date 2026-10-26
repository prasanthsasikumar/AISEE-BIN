package com.flowsxr.aiseebin.positioning

import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.Vec2
import kotlin.math.cos
import kotlin.math.sin

/** A position and heading on the floor plane (heading h faces (sin h, −cos h), as everywhere). */
data class FloorPose(val position: Vec2, val heading: Float)

/**
 * Ties ARCore's session frame to the route graph with Immersal fixes: iOS
 * `ImmersalAnchor` on the floor plane. ARCore tracks the phone smoothly from an
 * arbitrary origin; Immersal says where the camera is in the map now and then.
 * Each accepted fix pairs the two poses of one frame and refits the yaw plus
 * translation between them; every ARCore frame is then mapped through it.
 *
 * A fix that would move the visitor more than [maxJump] from where the anchor
 * puts them now is dropped as a mismatch; [maxRejections] in a row are believed,
 * since ARCore itself may have drifted or reset.
 */
class PlanarAnchor(private val maxJump: Float = 1.5f, private val maxRejections: Int = 3) {
    /** Graph-from-session: rotate by [yaw] (as `ImmersalAlignment.toGraph`), then translate. */
    data class Fit(val yaw: Float, val tx: Float, val tz: Float) {
        fun apply(session: FloorPose): FloorPose {
            val c = cos(yaw); val s = sin(yaw)
            val p = session.position
            return FloorPose(Vec2(c * p.x - s * p.z + tx, s * p.x + c * p.z + tz), Geometry.wrapAngle(session.heading + yaw))
        }
    }

    var fit: Fit? = null; private set
    var fixes = 0; private set
    var rejected = 0; private set
    var lastJump = 0f; private set
    private var consecutiveRejections = 0

    val isAnchored: Boolean get() = fit != null

    fun toGraph(session: FloorPose): FloorPose? = fit?.apply(session)

    /** Offers Immersal's camera pose (already in the graph frame) and ARCore's for the same frame. */
    fun update(graph: FloorPose, session: FloorPose): Boolean {
        val current = fit
        if (current != null) {
            lastJump = current.apply(session).position.distanceTo(graph.position)
            if (lastJump > maxJump) {
                consecutiveRejections++
                rejected++
                if (consecutiveRejections < maxRejections) return false
            }
        } else {
            lastJump = 0f
        }
        fit = fitOf(graph, session)
        fixes++
        consecutiveRejections = 0
        return true
    }

    fun reset() {
        fit = null; fixes = 0; rejected = 0; lastJump = 0f; consecutiveRejections = 0
    }

    companion object {
        fun fitOf(graph: FloorPose, session: FloorPose): Fit {
            val yaw = Geometry.wrapAngle(graph.heading - session.heading)
            val c = cos(yaw); val s = sin(yaw)
            val p = session.position
            return Fit(yaw, graph.position.x - (c * p.x - s * p.z), graph.position.z - (s * p.x + c * p.z))
        }
    }
}
