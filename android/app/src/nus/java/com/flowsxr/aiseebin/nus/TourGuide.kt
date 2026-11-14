package com.flowsxr.aiseebin.nus

import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.route.RouteGraph
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.abs

/** The visitor on the graph floor plane, with the camera height that says which floor. */
data class MapPose(val position: Vec2, val heading: Float, val height: Float)

/** What the tour needs from the rest of the app; the view model in the app, a fake in tests. */
interface TourHost {
    /** The tour's stops in map order (the tour's start point, if set, is not a stop). */
    val places: List<NavigationPoi>
    /** Where the visitor is, or null while the phone does not know. */
    val pose: MapPose?
    val graph: RouteGraph?
    fun navigate(poiId: String)
    fun stopNavigation()
    fun log(type: String, data: JSONObject = JSONObject())
}

enum class TourPhase {
    HOME,
    /** Walking (or waiting for a position) toward the current stop. */
    LEADING,
    /** At the current stop, showing its card. */
    ARRIVED,
    /** Tour over. */
    FINISHED,
}

data class TourState(
    /** The tour of every stop in order, or one chosen place. */
    val isTour: Boolean = true,
    val phase: TourPhase = TourPhase.HOME,
    val stops: List<NavigationPoi> = emptyList(),
    val index: Int = 0,
    /**
     * The tour was started before the phone knew where it is: the first stop
     * is picked (the nearest one) as soon as positioning is reliable.
     */
    val startPending: Boolean = false,
    /** A short line confirming what just changed ("Skipped Seating. Next: MPH 2"), shown for a few seconds. */
    val notice: String? = null,
) {
    val current: NavigationPoi? get() = stops.getOrNull(index)
    val next: NavigationPoi? get() = stops.getOrNull(index + 1)
    val isLastStop: Boolean get() = index >= stops.size - 1
}

/** What the visitor is doing: the tour of every location in order, or one place. Port of iOS `TourGuide`. */
class TourGuide(private val host: TourHost, private val scope: CoroutineScope?) {
    private val _state = MutableStateFlow(TourState())
    val state: StateFlow<TourState> = _state
    private var noticeJob: Job? = null

    fun levelName(poiId: String): String? = host.graph?.levels?.levelName(poiId)

    /**
     * Starts the tour where the visitor is: the nearest stop comes first and
     * the rest follow in tour order, wrapping round.
     */
    fun startTour() {
        val stops = host.places
        host.log("tour.start", JSONObject().put("stops", stops.size))
        _state.value = TourState(isTour = true, phase = TourPhase.LEADING, stops = stops, index = 0, startPending = true)
        if (host.pose != null) beginFromHere() else host.stopNavigation()
    }

    /** Called when positioning becomes reliable. */
    fun positionIsReliable() {
        val s = _state.value
        if (s.startPending && s.phase == TourPhase.LEADING && s.isTour) beginFromHere()
    }

    private fun beginFromHere() {
        val pose = host.pose ?: return
        val graph = host.graph
        var stops = _state.value.stops
        val first = graph?.let { nearestStopIndex(stops.map { it.id }, pose.position, pose.height, it) }
        if (first != null && first > 0) stops = stops.drop(first) + stops.take(first)
        _state.update { it.copy(startPending = false, stops = stops, index = 0) }
        host.log("tour.start_from", JSONObject().put("id", stops.firstOrNull()?.id ?: ""))
        leadToCurrent()
    }

    fun goTo(poi: NavigationPoi) {
        clearNotice()
        _state.value = TourState(isTour = false, phase = TourPhase.LEADING, stops = listOf(poi), index = 0)
        leadToCurrent()
    }

    fun nextStop() {
        val s = _state.value
        if (!s.isTour || s.isLastStop) { finish(); return }
        _state.update { it.copy(index = it.index + 1) }
        leadToCurrent()
    }

    /**
     * Moves on to the next stop and says so: the way to the next place often
     * starts along the same corridor, so nothing else on screen shows the skip.
     */
    fun skipStop() {
        val skipped = _state.value.current
        host.log("tour.skip", JSONObject().put("id", skipped?.id ?: ""))
        nextStop()
        val s = _state.value
        val next = s.current
        if (s.phase != TourPhase.LEADING || skipped == null || next == null) return
        show(skipNotice(skipped.name, next.name, levelName(next.id)))
    }

    private fun show(text: String) {
        _state.update { it.copy(notice = text) }
        noticeJob?.cancel()
        noticeJob = scope?.launch {
            delay(NOTICE_MS)
            _state.update { it.copy(notice = null) }
        }
    }

    private fun clearNotice() {
        noticeJob?.cancel()
        _state.update { it.copy(notice = null) }
    }

    fun exit() {
        val s = _state.value
        if ((s.phase == TourPhase.LEADING || s.phase == TourPhase.ARRIVED) && s.isTour) {
            host.log("tour.abandon", JSONObject().put("at", s.index))
        }
        host.stopNavigation()
        noticeJob?.cancel()
        _state.value = TourState()
    }

    private fun finish() {
        host.stopNavigation()
        val s = _state.value
        if (s.isTour) host.log("tour.end", JSONObject().put("stops", s.stops.size))
        _state.value = if (s.isTour) s.copy(phase = TourPhase.FINISHED, notice = null) else TourState()
    }

    private fun leadToCurrent() {
        val stop = _state.value.current ?: return finish()
        _state.update { it.copy(phase = TourPhase.LEADING) }
        host.navigate(stop.id)
    }

    /** The route to [id] ended there. */
    fun arrived(id: String) {
        val s = _state.value
        if (s.phase != TourPhase.LEADING || s.current?.id != id) return
        if (s.isTour) host.log("tour.stop_arrived", JSONObject().put("id", id).put("index", s.index))
        noticeJob?.cancel()
        _state.update { it.copy(phase = TourPhase.ARRIVED, notice = null) }
    }

    companion object {
        const val NOTICE_MS = 6000L

        /**
         * The stop closest to the visitor: planar distance plus a penalty for
         * being on another floor (the same weighting as the route search).
         */
        fun nearestStopIndex(stops: List<String>, here: Vec2, height: Float, graph: RouteGraph): Int? {
            var best: Pair<Int, Float>? = null
            for ((i, id) in stops.withIndex()) {
                val node = graph.node(id) ?: continue
                var d = node.position.distanceTo(here)
                graph.levels.heights[id]?.let { d += RouteGraph.HEIGHT_WEIGHT * abs(it - height) }
                if (best == null || d < best.second) best = i to d
            }
            return best?.first
        }

        fun skipNotice(skipped: String, next: String, level: String?): String =
            "Skipped $skipped. Next: $next" + (level?.let { ", $it" } ?: "")
    }
}
