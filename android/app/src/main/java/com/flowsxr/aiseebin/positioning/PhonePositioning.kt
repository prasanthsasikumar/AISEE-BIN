package com.flowsxr.aiseebin.positioning

import com.flowsxr.aiseebin.immersal.GlassesCamera
import com.flowsxr.aiseebin.immersal.GrayImage
import com.flowsxr.aiseebin.immersal.ImmersalPose
import com.flowsxr.aiseebin.immersal.LocalizeResult
import com.flowsxr.aiseebin.immersal.Localizer
import com.flowsxr.aiseebin.map.ImmersalAlignment
import com.flowsxr.aiseebin.map.Vec2
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One camera frame's luma and ARCore's intrinsics for it, at full size, copied out of ARCore. */
class PhoneShot(val image: GrayImage, val intrinsics: GlassesCamera.Intrinsics)

/**
 * Positions the phone with its own camera: iOS `PhoneImmersalLocalizer` on
 * ARCore. About once every [LOCALIZE_INTERVAL_MS], while ARCore is tracking, one
 * frame goes to the Immersal localizer with ARCore's own intrinsics; the
 * answer, carried into the graph by the map's alignment, is paired with
 * ARCore's pose for that frame in a [PlanarAnchor]. Between fixes every ARCore
 * frame is mapped through the anchor, so the position moves smoothly.
 *
 * Kept free of ARCore types: [onFrame] takes the floor pose and a way to grab
 * the image, so the rules can be tested off the phone.
 */
class PhonePositioning(private val scope: CoroutineScope) {
    private val _state = MutableStateFlow(PositioningState())
    val state: StateFlow<PositioningState> = _state

    /** Every position, on the main thread: Immersal fixes and the ARCore motion between them. */
    var onFix: ((Fix) -> Unit)? = null
    var onAttempt: ((String) -> Unit)? = null

    private val anchor = PlanarAnchor()
    @Volatile private var localizer: Localizer? = null
    @Volatile private var alignment: ImmersalAlignment? = null
    @Volatile private var generation = 0
    @Volatile private var inFlight = false
    private var lastAttempt = Long.MIN_VALUE / 2
    private var lastEmit = Long.MIN_VALUE / 2
    @Volatile private var lastMapId: Int? = null
    private var lastProblem: String? = "starting"

    fun start(localizer: Localizer, alignment: ImmersalAlignment) {
        stop()
        this.localizer = localizer
        this.alignment = alignment
        synchronized(anchor) { anchor.reset() }
        generation++
        inFlight = false
        lastAttempt = Long.MIN_VALUE / 2
        lastProblem = "starting"
        _state.value = PositioningState(running = true, localizer = localizer.label, tracking = "Starting the camera…")
    }

    fun stop() {
        val old = localizer ?: return
        localizer = null
        generation++
        _state.update { it.copy(running = false) }
        // Closing frees native maps; never on the caller's (GL or main) thread mid-localize.
        Thread({ old.close() }, "phone-localizer-close").start()
    }

    /**
     * Once per ARCore frame, on the GL thread. [session] is the camera's floor
     * pose in ARCore's frame, or null while ARCore is not tracking, with
     * [problem] saying why. [grab] copies the camera image; it is only called
     * when a localize is due.
     */
    fun onFrame(session: FloorPose?, problem: String?, nowMs: Long, grab: () -> PhoneShot?) {
        val loc = localizer ?: return
        val align = alignment ?: return
        if (session == null) {
            if (problem != lastProblem) { lastProblem = problem; _state.update { it.copy(tracking = problem) } }
            return
        }
        if (lastProblem != null) { lastProblem = null; _state.update { it.copy(tracking = null) } }

        val graph = synchronized(anchor) { anchor.toGraph(session) }
        if (graph != null && nowMs - lastEmit >= EMIT_INTERVAL_MS) {
            lastEmit = nowMs
            emit(Fix(graph.position, graph.heading, System.currentTimeMillis(), lastMapId))
        }

        if (inFlight || nowMs - lastAttempt < LOCALIZE_INTERVAL_MS) return
        val shot = grab() ?: return
        inFlight = true
        lastAttempt = nowMs
        val gen = generation
        scope.launch(Dispatchers.Default) {
            try {
                // Scaled here, off the GL thread; the intrinsics scale with the image.
                val sent = shot.image.scaledToWidth(SENT_WIDTH)
                val f = sent.width.toFloat() / shot.image.width
                val k = shot.intrinsics.let { GlassesCamera.Intrinsics(it.fx * f, it.fy * f, it.ox * f, it.oy * f) }
                val result = loc.localize(sent, k)
                if (gen == generation) apply(result, session, align, PhoneShot(sent, k))
            } finally {
                inFlight = false
            }
        }
    }

    private fun apply(result: LocalizeResult, session: FloorPose, alignment: ImmersalAlignment, shot: PhoneShot) {
        val planar = result.pose?.takeIf { result.success }?.let { ImmersalPose.planar(it) }
        var accepted = false
        var jump = 0f
        if (planar != null) {
            val graph = FloorPose(
                alignment.toGraph(Vec2(planar.x, planar.z), result.mapId),
                alignment.toGraphHeading(planar.heading, result.mapId),
            )
            synchronized(anchor) {
                accepted = anchor.update(graph, session)
                jump = anchor.lastJump
            }
            if (accepted) lastMapId = result.mapId
        }
        val counts = synchronized(anchor) { anchor.fixes to anchor.rejected }
        _state.update {
            it.copy(
                attempts = it.attempts + 1,
                fixes = counts.first,
                rejected = counts.second,
                lastLatencyMs = result.latencyMs,
                lastRequestBytes = result.requestBytes,
                frameSize = shot.image.width to shot.image.height,
                localizer = localizer?.label ?: it.localizer,
                lastError = when {
                    accepted -> null
                    planar != null -> "fix rejected: jumped %.1f m".format(jump)
                    else -> GlassesPositioning.describe(result.error)
                },
            )
        }
        onAttempt?.invoke("phone localize ${_state.value.attempts}: " + when {
            accepted -> "fix map=${result.mapId} jump %.1f m".format(jump)
            planar != null -> "rejected, jumped %.1f m".format(jump)
            else -> result.error
        } + " ${result.latencyMs} ms ${shot.image.width}x${shot.image.height}")
    }

    private fun emit(fix: Fix) {
        _state.update { it.copy(lastFix = fix) }
        scope.launch(Dispatchers.Main) { onFix?.invoke(fix) }
    }

    companion object {
        /** iOS `PhoneImmersalLocalizer.localizeInterval`. */
        const val LOCALIZE_INTERVAL_MS = 1200L
        /** How often ARCore motion between fixes becomes a position (announcements, the map). */
        const val EMIT_INTERVAL_MS = 200L
        /** iOS sends ARKit's 1920×1440 image at half size; ARCore's is scaled to the same width. */
        const val SENT_WIDTH = 960
    }
}
