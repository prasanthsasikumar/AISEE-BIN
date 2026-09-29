package com.flowsxr.aiseebin.positioning

import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.map.RelativeSide
import com.flowsxr.aiseebin.map.Vec2

/**
 * Drops a fix that jumps further than the visitor can have walked since the
 * last believed one (plus [slack]), and re-anchors after [maxRejections] in a
 * row so a genuinely moved visitor is not stuck. Port of iOS `FixGate`.
 */
class FixGate(private val slack: Float = 1.5f, private val maxRejections: Int = 3) {
    private var anchor: Pair<Vec2, Float>? = null
    private var consecutiveRejections = 0

    /** Metres the last evaluated fix jumped by, for diagnostics. */
    var lastJump = 0f
        private set

    /** @param walked metres walked since start; @return true when the fix should be used. */
    fun evaluate(position: Vec2, walked: Float): Boolean {
        val a = anchor ?: run { accept(position, walked); return true }
        lastJump = position.distanceTo(a.first)
        val allowed = maxOf(0f, walked - a.second) + slack
        if (lastJump <= allowed) { accept(position, walked); return true }
        consecutiveRejections++
        if (consecutiveRejections >= maxRejections) { accept(position, walked); return true }
        return false
    }

    fun reset() { anchor = null; consecutiveRejections = 0; lastJump = 0f }

    private fun accept(position: Vec2, walked: Float) {
        anchor = position to walked
        consecutiveRejections = 0
    }
}

data class ProximityAnnouncement(val poi: NavigationPoi, val side: RelativeSide, val distance: Float) {
    val spokenText: String
        get() {
            val lead = if (poi.category == PoiCategory.HAZARD) "Caution: ${poi.name}" else poi.name
            val base = "$lead ${side.phrase}."
            return poi.details?.takeIf { it.isNotBlank() }?.let { "$base $it" } ?: base
        }
}

/**
 * Speaks an exhibit or hazard once when the visitor enters its announce
 * radius, and re-arms only beyond 1.5× that radius so pacing at the edge does
 * not repeat it. Port of iOS `ProximityAnnouncer`.
 */
class ProximityAnnouncer(pois: List<NavigationPoi>) {
    private val pois = pois.filter { it.announceRadius > 0 }
    private val armed = this.pois.associate { it.id to true }.toMutableMap()

    fun update(position: Vec2, heading: Float): List<ProximityAnnouncement> {
        val out = mutableListOf<ProximityAnnouncement>()
        for (poi in pois) {
            val d = position.distanceTo(poi.position)
            val r = poi.announceRadius
            if (d <= r) {
                if (armed[poi.id] == true) {
                    armed[poi.id] = false
                    out += ProximityAnnouncement(poi, RelativeSide.of(Geometry.relativeBearing(position, heading, poi.position)), d)
                }
            } else if (d > r * 1.5f) {
                armed[poi.id] = true
            }
        }
        return out
    }
}
