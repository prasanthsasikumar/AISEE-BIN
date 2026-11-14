package com.flowsxr.aiseebin.positioning

import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.Vec2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * A position and heading on the floor plane (heading h faces (sin h, −cos h), as
 * everywhere), with the camera's height [y] for telling floors apart.
 */
data class FloorPose(val position: Vec2, val heading: Float, val y: Float = 0f)

/**
 * Ties ARCore's session frame to the route graph with Immersal fixes: iOS
 * `ImmersalAnchor`. ARCore tracks the phone smoothly from an arbitrary origin;
 * Immersal says where the camera is in the map now and then. Each accepted fix
 * pairs the two poses of one frame and refits the yaw plus translation between
 * them (both frames are gravity-aligned); every ARCore frame is then mapped
 * through it.
 *
 * A fix that would move the visitor more than [maxJump] from where the anchor
 * puts them now is dropped as a mismatch; [maxRejections] in a row are believed,
 * since ARCore itself may have drifted or reset. A jump beyond [farJump] cannot
 * be walking between fixes: far more often another scan matched a look-alike
 * spot, so it needs [maxRejectionsFar] in a row.
 */
class PlanarAnchor(
    private val maxJump: Float = 1.5f,
    private val maxRejections: Int = 3,
    private val farJump: Float = 8f,
    private val maxRejectionsFar: Int = 6,
) {
    /** Graph-from-session: rotate by [yaw] (as `ImmersalAlignment.toGraph`), then translate. */
    data class Fit(val yaw: Float, val tx: Float, val tz: Float, val ty: Float = 0f) {
        fun apply(session: FloorPose): FloorPose {
            val c = cos(yaw); val s = sin(yaw)
            val p = session.position
            return FloorPose(Vec2(c * p.x - s * p.z + tx, s * p.x + c * p.z + tz), Geometry.wrapAngle(session.heading + yaw), session.y + ty)
        }

        /** A graph point (x, height, z) in the session frame, for drawing on the camera view. */
        fun toSession(x: Float, y: Float, z: Float): FloatArray {
            val c = cos(yaw); val s = sin(yaw)
            val dx = x - tx; val dz = z - tz
            return floatArrayOf(c * dx + s * dz, y - ty, -s * dx + c * dz)
        }

        /** A graph direction on the floor plane, in the session frame. */
        fun toSessionDirection(d: Vec2): Vec2 {
            val c = cos(yaw); val s = sin(yaw)
            return Vec2(c * d.x + s * d.z, -s * d.x + c * d.z)
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
                val needed = if (lastJump > farJump) maxRejectionsFar else maxRejections
                if (consecutiveRejections < needed) return false
            }
        } else {
            lastJump = 0f
        }
        fit = fitOf(graph, session)
        fixes++
        consecutiveRejections = 0
        return true
    }

    /** Adopts a fit made elsewhere as a first fix (debug: standing the phone at a place). */
    fun install(fit: Fit) {
        this.fit = fit
        fixes++
        consecutiveRejections = 0
        lastJump = 0f
    }

    /**
     * Forgets the fit but keeps the counts: ARCore's session frame has moved
     * under it ([SessionJumpDetector]). Nothing maps until the next fix, which
     * is taken as a first fix.
     */
    fun invalidate() {
        fit = null; consecutiveRejections = 0; lastJump = 0f
    }

    fun reset() {
        fit = null; fixes = 0; rejected = 0; lastJump = 0f; consecutiveRejections = 0
    }

    companion object {
        fun fitOf(graph: FloorPose, session: FloorPose): Fit {
            val yaw = Geometry.wrapAngle(graph.heading - session.heading)
            val c = cos(yaw); val s = sin(yaw)
            val p = session.position
            return Fit(yaw, graph.position.x - (c * p.x - s * p.z), graph.position.z - (s * p.x + c * p.z), graph.y - session.y)
        }
    }
}

/**
 * Notices the AR session moving its own frame (iOS `SessionJumpDetector`): a
 * step between consecutive tracked poses longer than walking allows. Guidance
 * trusts the session to carry the position between fixes; when it re-places
 * its frame in one step, every fit made in the old frame is void.
 *
 * Feed it tracking poses only, in order. The allowance grows with the time
 * since the last one, so a pause in tracking does not by itself count.
 */
class SessionJumpDetector(private val slack: Float = 2f, private val maxSpeed: Float = 4f) {
    private var last: Triple<Vec2, Float, Long>? = null

    /** The metres jumped when this pose cannot follow the last one by walking; null otherwise. */
    fun jump(session: FloorPose, atMs: Long): Float? {
        val previous = last
        last = Triple(session.position, session.y, atMs)
        if (previous == null || atMs < previous.third) return null
        val planar = session.position.distanceTo(previous.first)
        val moved = hypot(planar, session.y - previous.second)
        return if (moved > slack + maxSpeed * (atMs - previous.third) / 1000f) moved else null
    }

    fun reset() { last = null }
}
