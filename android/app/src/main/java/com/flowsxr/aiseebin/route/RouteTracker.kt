package com.flowsxr.aiseebin.route

import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.map.Vec2
import kotlin.math.abs

/** Tunable distances and timings for guidance. Metres and seconds (iOS `GuidanceThresholds`). */
data class GuidanceThresholds(
    /** Announce the upcoming turn when the next node is this close. */
    val approachDistance: Float = 3.0f,
    /** Treat the node as reached when this close. */
    val arrivalDistance: Float = 1.5f,
    /** Consider the user off-route beyond this distance from the current leg. */
    val offRouteDistance: Float = 2.5f,
    /** Reassurance cadence while walking a long leg. */
    val progressReminderInterval: Double = 12.0,
    /** Cadence for repeating "off route" / "relocalizing" warnings. */
    val offRouteRepeatInterval: Double = 8.0,
)

/** Discrete progress while following a route. */
sealed interface RouteEvent {
    data object None : RouteEvent
    /** Arrived at an intermediate node (id). */
    data class ReachedNode(val id: String) : RouteEvent
    /** Arrived at the destination (id). */
    data class Arrived(val id: String) : RouteEvent
}

/**
 * Walks a path from [RouteGraph.findPath] and decides when the visitor has
 * reached the next node, has arrived, or has strayed from the current leg.
 * Port of iOS `RouteTracker`.
 *
 * The path's first node is the node nearest the visitor, so the first target
 * is index 1. A one-node path (the nearest node is the destination) still has
 * to be walked to, so its only node is the target.
 */
class RouteTracker(
    val path: List<NavigationPoi>,
    private val thresholds: GuidanceThresholds = GuidanceThresholds(),
    /** Camera height per node id (`BuildingLevels.heights`); empty on maps without heights. */
    private val heights: Map<String, Float> = emptyMap(),
    /**
     * Where the visitor stood when the route was planned. They rarely stand on
     * the graph, so on the first leg the straight line from here to the target
     * is as much "the route" as the graph edge is.
     */
    private val origin: Vec2? = null,
) {
    var targetIndex = if (path.size > 1) 1 else 0
        private set
    private val firstTargetIndex = targetIndex

    val hasArrived: Boolean get() = targetIndex >= path.size
    /** The node the visitor is walking toward, or null once arrived. */
    val targetNode: NavigationPoi? get() = if (hasArrived) null else path[targetIndex]
    private val previousNode: NavigationPoi? get() = path.getOrNull(targetIndex - 1)
    val isFinalLeg: Boolean get() = targetIndex == path.size - 1

    /** Index of the next named place from the current target on, else the destination; null once arrived. */
    private val spokenTargetIndex: Int?
        get() {
            if (hasArrived) return null
            for (i in targetIndex until path.size) if (path[i].category != PoiCategory.JUNCTION) return i
            return path.size - 1
        }

    /** Name to show for the current target: waypoints are skipped in favour of the next named place. */
    val spokenTargetName: String? get() = spokenTargetIndex?.let { path[it].name }

    /** Metres to walk along the route to the place [spokenTargetName] names. 0 once arrived. */
    fun distanceToSpokenTarget(position: Vec2): Float {
        val target = targetNode ?: return 0f
        val end = spokenTargetIndex ?: return 0f
        var total = position.distanceTo(target.position)
        for (i in targetIndex until end) total += path[i].position.distanceTo(path[i + 1].position)
        return total
    }

    /** Advances the target when the visitor is within the arrival radius (and, with heights, on its floor). */
    fun update(position: Vec2, height: Float? = null): RouteEvent {
        val target = targetNode ?: return RouteEvent.None
        if (position.distanceTo(target.position) > thresholds.arrivalDistance) return RouteEvent.None
        val targetHeight = heights[target.id]
        // Standing under the top of the stairs is not arriving there.
        if (height != null && targetHeight != null && abs(height - targetHeight) > REACH_HEIGHT_TOLERANCE) return RouteEvent.None
        targetIndex++
        return if (hasArrived) RouteEvent.Arrived(target.id) else RouteEvent.ReachedNode(target.id)
    }

    fun isOffRoute(position: Vec2): Boolean {
        val distance = distanceFromLeg(position) ?: return false
        return distance > thresholds.offRouteDistance
    }

    /** Metres from the current leg, or null once arrived. */
    fun distanceFromLeg(position: Vec2): Float? {
        val target = targetNode ?: return null
        val from = previousNode?.position ?: target.position
        val fromLeg = Geometry.distanceToSegment(position, from, target.position)
        val start = origin
        if (targetIndex != firstTargetIndex || start == null) return fromLeg
        return minOf(fromLeg, Geometry.distanceToSegment(position, start, target.position))
    }

    /** Metres to walk: current leg remainder plus all following edges. */
    fun remainingDistance(position: Vec2): Float {
        val target = targetNode ?: return 0f
        var total = position.distanceTo(target.position)
        for (i in targetIndex until path.size - 1) total += path[i].position.distanceTo(path[i + 1].position)
        return total
    }

    companion object {
        /** A node counts as reached only within this height of it. */
        const val REACH_HEIGHT_TOLERANCE = 1.5f
    }
}
