package com.flowsxr.aiseebin.route

import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.Vec2
import kotlin.math.abs

/** How a route crosses between levels. */
enum class LevelChangeKind(val word: String) { STAIRS("stairs"), LIFT("lift") }

/** One staircase or lift ride on a route (indices into the route's nodes). */
data class StairRun(
    /** The last node before the first step (or the lift door). */
    val start: Int,
    /** The first node after the last step. */
    val end: Int,
    val kind: LevelChangeKind,
    val up: Boolean,
    val toLevel: Int,
)

/**
 * The floors of a building, worked out from the heights at which places were
 * marked (`NavigationPoi.y`). A map without heights is one level, so every
 * answer here degrades to "same floor". Port of iOS `BuildingLevels`.
 *
 * Waypoints without a height of their own take the height of the nearest node
 * (by hops) that has one.
 */
class BuildingLevels(map: NavigationMap) {
    /** Height (camera, metres) per POI id, filled for waypoints; empty when the map has no heights at all. */
    val heights: Map<String, Float>
    /** Mean camera height of each level, lowest first. */
    val levelHeights: List<Float>
    private val names: Map<String, String>
    /** Places whose height was measured, not inherited from a neighbour. */
    private val measured: Set<String>
    private val planar: Map<String, Vec2>

    init {
        val names = LinkedHashMap<String, String>()
        val planar = LinkedHashMap<String, Vec2>()
        val known = LinkedHashMap<String, Float>()
        for (poi in map.pois) {
            names.putIfAbsent(poi.id, poi.name)
            planar.putIfAbsent(poi.id, poi.position)
            poi.y?.let { known[poi.id] = it }
        }
        this.names = names
        this.planar = planar
        measured = known.keys.toSet()
        if (known.isEmpty()) {
            heights = emptyMap()
            levelHeights = emptyList()
        } else {
            // Breadth-first from every node with a height: a waypoint takes its nearest one.
            val adjacency = HashMap<String, MutableList<String>>()
            for (edge in map.edges) {
                adjacency.getOrPut(edge.from) { mutableListOf() }.add(edge.to)
                adjacency.getOrPut(edge.to) { mutableListOf() }.add(edge.from)
            }
            val filled = HashMap<String, Float>(known)
            var frontier = map.pois.map { it.id }.filter { it in known }
            while (frontier.isNotEmpty()) {
                val next = mutableListOf<String>()
                for (id in frontier) {
                    for (other in adjacency[id].orEmpty()) {
                        if (other in filled) continue
                        filled[other] = filled.getValue(id)
                        next += other
                    }
                }
                frontier = next
            }
            heights = filled
            // A map made from a recorded walk has a height on every node, the
            // steps of a staircase and the length of a ramp included. Those
            // in-between heights would join the floors into one, so the floors
            // are found from the level ground: every measured place that is not
            // at either end of an edge that rises.
            val rising = HashSet<String>()
            for (edge in map.edges) {
                val a = known[edge.from] ?: continue
                val b = known[edge.to] ?: continue
                val pa = planar[edge.from] ?: continue
                val pb = planar[edge.to] ?: continue
                // Steeper than 4% and more than the wobble of a hand-held height.
                val rise = abs(b - a)
                if (rise > 0.15f && rise > 0.04f * pa.distanceTo(pb)) { rising += edge.from; rising += edge.to }
            }
            val level = known.filterKeys { it !in rising }
            levelHeights = cluster((level.ifEmpty { known }).values.toList())
        }
    }

    val isMultiLevel: Boolean get() = levelHeights.size > 1

    /** 1-based level for a camera height: the nearest level's mean. */
    fun level(forHeight: Float): Int {
        if (levelHeights.isEmpty()) return 1
        var best = 0
        for ((i, h) in levelHeights.withIndex()) if (abs(h - forHeight) < abs(levelHeights[best] - forHeight)) best = i
        return best + 1
    }

    /** 1-based level of a place; 1 when the map has no heights. */
    fun levelOf(poiId: String): Int = heights[poiId]?.let { level(it) } ?: 1

    /** "Level 2", or null for a single-level map (no point labelling it). */
    fun levelName(poiId: String): String? = if (isMultiLevel) "Level ${levelOf(poiId)}" else null

    /** Floor height (metres, graph frame) under a place, for drawing on the floor. */
    fun floorHeight(poiId: String): Float? = heights[poiId]?.let { it - CAMERA_HEIGHT }

    /**
     * Whether walking from [a] to [b] changes level, and how. A lift is named
     * as one ("Lift", "Elevator") at either end; anything else is stairs.
     * Walking up a ramp between two measured heights is not a level change.
     */
    fun levelChange(a: String, b: String): LevelChangeKind? {
        if (levelOf(a) == levelOf(b)) return null
        if (a in measured && b in measured) {
            val ya = heights[a]; val yb = heights[b]; val pa = planar[a]; val pb = planar[b]
            if (ya != null && yb != null && pa != null && pb != null && !isSteep(yb - ya, pa.distanceTo(pb))) return null
        }
        val lift = listOfNotNull(names[a], names[b]).any { n -> n.lowercase().let { "lift" in it || "elevator" in it } }
        return if (lift) LevelChangeKind.LIFT else LevelChangeKind.STAIRS
    }

    /**
     * The next stairs or lift on [path]: the first one whose far end is at or
     * after [target], the index of the node the visitor is heading to.
     *
     * A level changes on one edge, which on a real staircase falls somewhere in
     * the middle. The edges either side that also climb belong to the same
     * staircase, so `start` is its first step and `end` its last. Where the
     * heights were measured the climb itself says so; where they were
     * inherited, nodes named as stairs ("MPH stairs 3") do.
     */
    fun stairRun(path: List<String>, target: Int): StairRun? {
        if (path.size < 2) return null
        fun isStair(i: Int) = names[path[i]]?.lowercase()?.contains("stair") ?: false
        /** Whether the edge from node `i` to the next is part of a staircase. */
        fun climbs(i: Int): Boolean {
            val a = path[i]; val b = path[i + 1]
            if (a in measured && b in measured) {
                val ya = heights[a]; val yb = heights[b]; val pa = planar[a]; val pb = planar[b]
                if (ya != null && yb != null && pa != null && pb != null) return isSteep(yb - ya, pa.distanceTo(pb))
            }
            return isStair(i) && isStair(i + 1)
        }
        for (i in 0 until path.size - 1) {
            val kind = levelChange(path[i], path[i + 1]) ?: continue
            var start = i
            var end = i + 1
            if (kind == LevelChangeKind.STAIRS) {
                while (start > 0 && climbs(start - 1)) start--
                while (end < path.size - 1 && climbs(end)) end++
            }
            if (end < target) continue
            val to = levelOf(path[i + 1])
            return StairRun(start, end, kind, up = to > levelOf(path[i]), toLevel = to)
        }
        return null
    }

    companion object {
        /** Two marked heights further apart than this are on different levels. A storey is ~3–4 m. */
        const val LEVEL_GAP = 2.0f
        /** Typical camera height above the floor when a place is marked. */
        const val CAMERA_HEIGHT = 1.35f
        /** A rise of more than this over a short enough run is a step, not a floor. */
        const val STEP_RISE = 0.25f
        const val STEP_SLOPE = 0.15f

        /** Whether going from one measured height to another this far apart climbs like stairs. */
        fun isSteep(rise: Float, run: Float) = abs(rise) > STEP_RISE && abs(rise) > STEP_SLOPE * run

        /** Groups sorted heights wherever consecutive values jump by more than [LEVEL_GAP]. */
        fun cluster(values: List<Float>): List<Float> {
            val sorted = values.sorted()
            if (sorted.isEmpty()) return emptyList()
            val means = mutableListOf<Float>()
            var group = mutableListOf(sorted.first())
            for (v in sorted.drop(1)) {
                if (v - group.last() > LEVEL_GAP) {
                    means += group.sum() / group.size
                    group = mutableListOf(v)
                } else {
                    group += v
                }
            }
            means += group.sum() / group.size
            return means
        }
    }
}
