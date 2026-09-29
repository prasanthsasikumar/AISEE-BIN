package com.flowsxr.aiseebin.map

import org.json.JSONObject
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** A point on the floor plane: x right, z toward the viewer at the origin (ARKit's convention). */
data class Vec2(val x: Float, val z: Float) {
    operator fun minus(o: Vec2) = Vec2(x - o.x, z - o.z)
    operator fun plus(o: Vec2) = Vec2(x + o.x, z + o.z)
    operator fun times(s: Float) = Vec2(x * s, z * s)
    fun length() = hypot(x, z)
    fun distanceTo(o: Vec2) = (this - o).length()
}

enum class PoiCategory { DESTINATION, JUNCTION, EXHIBIT, HAZARD;
    companion object {
        fun parse(raw: String?) = when (raw) {
            "junction" -> JUNCTION
            "exhibit" -> EXHIBIT
            "hazard" -> HAZARD
            else -> DESTINATION
        }
    }
}

data class NavigationPoi(
    val id: String,
    val name: String,
    val position: Vec2,
    val category: PoiCategory,
    val details: String?,
    /** Radius set in the web editor (`announceRadius`), metres; null means the default. */
    val customAnnounceRadius: Float? = null,
) {
    val isNamed: Boolean get() = category != PoiCategory.JUNCTION

    /** Metres within which this place is announced while walking; 0 = never (iOS `NavigationPOI.announceRadius`). */
    val announceRadius: Float
        get() {
            if (category != PoiCategory.EXHIBIT && category != PoiCategory.HAZARD) return 0f
            val custom = customAnnounceRadius
            return if (custom != null && custom in ANNOUNCE_RADIUS_RANGE) custom else DEFAULT_ANNOUNCE_RADIUS
        }

    companion object {
        const val DEFAULT_ANNOUNCE_RADIUS = 2.5f
        val ANNOUNCE_RADIUS_RANGE = 0.5f..20f
    }
}

data class NavigationEdge(val from: String, val to: String)

/**
 * Immersal map space → graph frame, a yaw about the vertical plus a floor
 * translation (iOS `ImmersalAlignment`). Editor-drawn and scan maps are identity.
 */
data class ImmersalAlignment(
    val mapIds: List<Int>,
    val yaw: Float,
    val tx: Float,
    val tz: Float,
    val pairCount: Int,
    val origin: String?,
) {
    fun toGraph(p: Vec2): Vec2 {
        val c = cos(yaw); val s = sin(yaw)
        return Vec2(c * p.x - s * p.z + tx, s * p.x + c * p.z + tz)
    }

    fun toGraphHeading(heading: Float) = Geometry.wrapAngle(heading + yaw)
}

/** The same graph JSON the iOS app and the web editor read and write. */
data class NavigationMap(
    val name: String,
    val pois: List<NavigationPoi>,
    val edges: List<NavigationEdge>,
    val alignment: ImmersalAlignment?,
) {
    companion object {
        fun parse(json: JSONObject): NavigationMap {
            val pois = json.optJSONArray("pois")?.let { arr ->
                (0 until arr.length()).map { i ->
                    val p = arr.getJSONObject(i)
                    NavigationPoi(
                        id = p.getString("id"),
                        name = if (p.isNull("name")) p.getString("id") else p.optString("name").ifBlank { p.getString("id") },
                        position = Vec2(p.optDouble("x", 0.0).toFloat(), p.optDouble("z", 0.0).toFloat()),
                        category = PoiCategory.parse(p.optString("category", "destination")),
                        details = if (p.isNull("details")) null else p.optString("details").ifBlank { null },
                        customAnnounceRadius = if (p.has("announceRadius") && !p.isNull("announceRadius"))
                            p.optDouble("announceRadius", Double.NaN).toFloat().takeIf { it.isFinite() } else null,
                    )
                }
            } ?: emptyList()
            val edges = json.optJSONArray("edges")?.let { arr ->
                (0 until arr.length()).map { i ->
                    val e = arr.getJSONObject(i)
                    NavigationEdge(e.getString("from"), e.getString("to"))
                }
            } ?: emptyList()
            val alignment = json.optJSONObject("immersalAlignment")?.let { a ->
                val ids = a.optJSONArray("mapIDs")
                ImmersalAlignment(
                    mapIds = ids?.let { arr -> (0 until arr.length()).map { arr.getInt(it) } } ?: emptyList(),
                    yaw = a.optDouble("yaw", 0.0).toFloat(),
                    tx = a.optDouble("tx", 0.0).toFloat(),
                    tz = a.optDouble("tz", 0.0).toFloat(),
                    pairCount = a.optInt("pairCount", 0),
                    origin = if (a.isNull("origin")) null else a.optString("origin").ifBlank { null },
                )
            }
            return NavigationMap(json.optString("name", "Map"), pois, edges, alignment)
        }
    }
}

object Geometry {
    fun wrapAngle(angle: Float): Float {
        var a = (angle % (2 * PI)).toFloat()
        if (a <= -PI) a += (2 * PI).toFloat()
        if (a > PI) a -= (2 * PI).toFloat()
        return a
    }

    /** Signed turn from `heading` to face `target`; positive means turn right. */
    fun relativeBearing(from: Vec2, heading: Float, to: Vec2): Float {
        val d = to - from
        return wrapAngle(atan2(d.x, -d.z) - heading)
    }

    fun distanceToSegment(p: Vec2, a: Vec2, b: Vec2): Float {
        val ab = b - a
        val len2 = ab.x * ab.x + ab.z * ab.z
        if (len2 == 0f) return p.distanceTo(a)
        val t = (((p.x - a.x) * ab.x + (p.z - a.z) * ab.z) / len2).coerceIn(0f, 1f)
        return p.distanceTo(a + ab * t)
    }
}

enum class RelativeSide(val phrase: String) {
    AHEAD("ahead"), LEFT("on your left"), RIGHT("on your right"), BEHIND("behind you");

    companion object {
        fun of(relativeAngle: Float): RelativeSide {
            val deg = Math.toDegrees(relativeAngle.toDouble())
            return when {
                deg in -45.0..45.0 -> AHEAD
                deg > 45 && deg < 135 -> RIGHT
                deg < -45 && deg > -135 -> LEFT
                else -> BEHIND
            }
        }
    }
}

/** "Where am I" in terms of named places only, worded as on iOS (`LocationDescriber`). */
class LocationDescriber(map: NavigationMap) {
    private val pois = map.pois.associateBy { it.id }
    private val edges = map.edges.filter { pois[it.from] != null && pois[it.to] != null }
    private val neighbours: Map<String, List<String>> = buildMap<String, MutableList<String>> {
        for (e in edges) {
            getOrPut(e.from) { mutableListOf() }.add(e.to)
            getOrPut(e.to) { mutableListOf() }.add(e.from)
        }
    }

    fun describe(position: Vec2, heading: Float): String? {
        val nearest = pois.values.filter { it.isNamed }.minByOrNull { it.position.distanceTo(position) } ?: return null
        val straight = nearest.position.distanceTo(position)
        if (straight <= AT_RADIUS) return "You are at the ${nearest.name}."

        val edge = edges.minByOrNull { edgeDistance(it, position) }
        if (edge != null && edgeDistance(edge, position) <= ON_EDGE_RADIUS) {
            val from = pois.getValue(edge.from); val to = pois.getValue(edge.to)
            val candidates = listOfNotNull(
                nearestNamed(from.id, to.id, position.distanceTo(from.position))?.let { Triple(it.first, it.second, from) },
                nearestNamed(to.id, from.id, position.distanceTo(to.position))?.let { Triple(it.first, it.second, to) },
            ).sortedBy { it.second }
            val nearer = candidates.firstOrNull()
            if (nearer != null) {
                val side = RelativeSide.of(Geometry.relativeBearing(position, heading, nearer.third.position))
                val farther = candidates.drop(1).firstOrNull { it.first.id != nearer.first.id }
                return if (farther != null) {
                    "You are between the ${nearer.first.name} and the ${farther.first.name}, about " +
                        "${metres(nearer.second)} from the ${nearer.first.name}, ${side.phrase}."
                } else {
                    "You are about ${metres(nearer.second)} from the ${nearer.first.name}, ${side.phrase}."
                }
            }
        }
        val side = RelativeSide.of(Geometry.relativeBearing(position, heading, nearest.position))
        return "You are about ${metres(straight)} from the ${nearest.name}, ${side.phrase}."
    }

    private fun edgeDistance(e: NavigationEdge, p: Vec2): Float {
        val a = pois[e.from] ?: return Float.MAX_VALUE
        val b = pois[e.to] ?: return Float.MAX_VALUE
        return Geometry.distanceToSegment(p, a.position, b.position)
    }

    /** Dijkstra from `start` to the closest named place, never through `excluded`. */
    private fun nearestNamed(start: String, excluded: String, startDistance: Float): Pair<NavigationPoi, Float>? {
        val best = mutableMapOf(start to startDistance)
        val frontier = mutableListOf(start to startDistance)
        val visited = mutableSetOf(excluded)
        while (frontier.isNotEmpty()) {
            frontier.sortBy { it.second }
            val (id, d) = frontier.removeAt(0)
            if (id in visited) continue
            val node = pois[id] ?: continue
            visited += id
            if (node.isNamed) return node to d
            for (next in neighbours[id].orEmpty()) {
                if (next in visited) continue
                val np = pois[next] ?: continue
                val nd = d + node.position.distanceTo(np.position)
                if (nd < (best[next] ?: Float.MAX_VALUE)) { best[next] = nd; frontier += next to nd }
            }
        }
        return null
    }

    companion object {
        const val AT_RADIUS = 2.0f
        const val ON_EDGE_RADIUS = 4.0f
        fun metres(v: Float): String {
            val n = maxOf(1, Math.round(v))
            return if (n == 1) "1 meter" else "$n meters"
        }
    }
}
