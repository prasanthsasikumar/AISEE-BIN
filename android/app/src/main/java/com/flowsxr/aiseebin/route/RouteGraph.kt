package com.flowsxr.aiseebin.route

import android.util.Log
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.Vec2
import java.util.PriorityQueue
import kotlin.math.abs

/**
 * The map as a graph: route search and "which node am I nearest". Port of iOS
 * `PathfindingEngine` (GameplayKit's A* there; the same shortest path by floor
 * distance here).
 */
class RouteGraph(val map: NavigationMap) {
    /** Floors, from the heights places were marked at; one level on old maps. */
    val levels = BuildingLevels(map)
    private val nodes: Map<String, NavigationPoi> = LinkedHashMap<String, NavigationPoi>().apply {
        for (poi in map.pois) putIfAbsent(poi.id, poi)
    }
    private val neighbours: Map<String, List<String>>

    init {
        val adjacency = HashMap<String, MutableList<String>>()
        for (edge in map.edges) {
            // A server edit can leave a path to a place that was deleted; the rest of the map still works.
            if (edge.from !in nodes || edge.to !in nodes) {
                runCatching { Log.w("RouteGraph", "edge to an unknown node skipped: ${edge.from} → ${edge.to}") }
                continue
            }
            adjacency.getOrPut(edge.from) { mutableListOf() }.add(edge.to)
            adjacency.getOrPut(edge.to) { mutableListOf() }.add(edge.from)
        }
        neighbours = adjacency
    }

    fun node(id: String): NavigationPoi? = nodes[id]

    /** Whether any path touches this node. */
    fun isConnected(id: String) = !neighbours[id].isNullOrEmpty()

    /** The node closest to a floor-plane position. */
    fun nearestNode(position: Vec2): NavigationPoi? = nodes.values.minByOrNull { it.position.distanceTo(position) }

    /**
     * The nearest node allowing for floors: planar distance plus
     * [HEIGHT_WEIGHT] × the height difference, for nodes whose height is
     * known. Without a camera height, or on a map without heights, this is
     * [nearestNode] by floor distance alone.
     */
    fun nearestNode(position: Vec2, height: Float?): NavigationPoi? {
        if (height == null || levels.heights.isEmpty()) return nearestNode(position)
        return nodes.values.minByOrNull { node ->
            val planar = node.position.distanceTo(position)
            levels.heights[node.id]?.let { planar + HEIGHT_WEIGHT * abs(it - height) } ?: planar
        }
    }

    /** Shortest path between two node ids by floor distance; empty when either is unknown or no route exists. */
    fun findPath(from: String, to: String): List<NavigationPoi> {
        val start = nodes[from] ?: return emptyList()
        val goal = nodes[to] ?: return emptyList()
        if (start.id == goal.id) return listOf(start)
        val best = HashMap<String, Float>().apply { put(start.id, 0f) }
        val cameFrom = HashMap<String, String>()
        val done = HashSet<String>()
        // A*: cost so far plus the straight line to the goal.
        val open = PriorityQueue<Pair<String, Float>>(compareBy { it.second })
        open += start.id to start.position.distanceTo(goal.position)
        while (open.isNotEmpty()) {
            val id = open.poll()!!.first
            if (!done.add(id)) continue
            if (id == goal.id) break
            val here = nodes.getValue(id)
            val cost = best.getValue(id)
            for (next in neighbours[id].orEmpty()) {
                if (next in done) continue
                val node = nodes.getValue(next)
                val candidate = cost + here.position.distanceTo(node.position)
                if (candidate < (best[next] ?: Float.MAX_VALUE)) {
                    best[next] = candidate
                    cameFrom[next] = id
                    open += next to candidate + node.position.distanceTo(goal.position)
                }
            }
        }
        if (goal.id !in cameFrom) return emptyList()
        val path = ArrayList<NavigationPoi>()
        var at: String? = goal.id
        while (at != null) { path += nodes.getValue(at); at = cameFrom[at] }
        return path.reversed()
    }

    companion object {
        /**
         * Weight of height difference against floor distance when snapping: a
         * node one storey up (~3.5 m) counts as ~10 m away, so the one on your
         * own floor wins.
         */
        const val HEIGHT_WEIGHT = 3f
    }
}
