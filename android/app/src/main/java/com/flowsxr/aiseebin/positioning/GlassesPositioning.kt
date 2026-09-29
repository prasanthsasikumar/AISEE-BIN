package com.flowsxr.aiseebin.positioning

import com.flowsxr.aiseebin.glasses.TimedFrame
import com.flowsxr.aiseebin.immersal.GlassesCamera
import com.flowsxr.aiseebin.immersal.GrayImage
import com.flowsxr.aiseebin.immersal.ImmersalClient
import com.flowsxr.aiseebin.immersal.Localizer
import com.flowsxr.aiseebin.immersal.ImmersalPose
import com.flowsxr.aiseebin.immersal.LocalizeResult
import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.ImmersalAlignment
import com.flowsxr.aiseebin.map.Vec2
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

data class Fix(val position: Vec2, val heading: Float, val atMillis: Long, val mapId: Int?)

data class PositioningState(
    val running: Boolean = false,
    val attempts: Int = 0,
    val fixes: Int = 0,
    val lastLatencyMs: Long? = null,
    val lastRequestBytes: Int? = null,
    val lastError: String? = null,
    val lastFix: Fix? = null,
    val frameSize: Pair<Int, Int>? = null,
    /** "on-device" or "cloud". */
    val localizer: String? = null,
)

/**
 * Glasses → Immersal → graph position, the Android half of iOS
 * `GlassesPositioning` without the pedometer: one request in flight at a time,
 * at most one a second, each fix carried into the graph frame by the map's
 * alignment. Positions stay where the last fix put them until the next one.
 */
class GlassesPositioning(
    private val scope: CoroutineScope,
    private val latestFrame: () -> TimedFrame?,
    private val debugDir: File?,
) {
    private val _state = MutableStateFlow(PositioningState())
    val state: StateFlow<PositioningState> = _state

    /** Called on the positioning thread for every accepted fix. */
    var onFix: ((Fix) -> Unit)? = null

    /** Called on the positioning thread after every attempt, with a one-line summary. */
    var onAttempt: ((String) -> Unit)? = null

    private var job: Job? = null

    @Volatile private var localizer: Localizer? = null
    /** Bumped by every start/stop; a loop whose generation is stale writes nothing. */
    @Volatile private var generation = 0

    fun start(localizer: Localizer, alignment: ImmersalAlignment, camera: GlassesCamera) {
        stop()
        this.localizer = localizer
        val gen = ++generation
        _state.value = PositioningState(running = true, localizer = localizer.label)
        job = scope.launch(Dispatchers.IO) {
            var lastStart = 0L
            var lastSeq = Long.MIN_VALUE
            while (isActive) {
                val wait = MIN_INTERVAL_MS - (System.currentTimeMillis() - lastStart)
                if (wait > 0) delay(wait)
                val frame = latestFrame()
                val age = frame?.let { System.currentTimeMillis() - it.capturedAtMillis }
                // A stalled stream leaves its last frame behind: never localize it twice,
                // or present an old view as a fresh position.
                if (frame == null || frame.seq == lastSeq || age!! > MAX_FRAME_AGE_MS) {
                    _state.update { it.copy(lastError = if (frame == null) "waiting for glasses video" else "no new glasses video") }
                    delay(300)
                    continue
                }
                lastSeq = frame.seq
                lastStart = System.currentTimeMillis()
                val sent = frame.image.scaledToWidth(SENT_WIDTH)
                if (_state.value.attempts < 3 || _state.value.attempts % 20 == 0) {
                    debugDir?.let { runCatching { File(it, "immersal-last.png").writeBytes(sent.toPng()) } }
                }
                val result = localizer.localize(sent, camera.intrinsics(sent.width, sent.height))
                if (!isActive || gen != generation) break
                apply(result, alignment, sent, frame.capturedAtMillis, localizer.label)
            }
        }
    }

    fun stop() {
        generation++
        job?.cancel()
        job = null
        val old = localizer
        localizer = null
        // close() waits for an in-flight native call and refuses later ones. A plain
        // thread, not the scope: this also runs from onCleared after the scope is cancelled.
        old?.let { Thread({ it.close() }, "localizer-close").start() }
        _state.update { it.copy(running = false) }
    }

    private fun apply(result: LocalizeResult, alignment: ImmersalAlignment, sent: GrayImage, capturedAt: Long, label: String) {
        onAttempt?.invoke("localize ${_state.value.attempts + 1} ($label): " +
            "${if (result.success) "fix" else describe(result.error)} map=${result.mapId ?: "-"} " +
            "${result.latencyMs} ms ${result.requestBytes} B")
        val planar = result.pose?.takeIf { result.success }?.let { ImmersalPose.planar(it) }
        if (planar == null) {
            _state.update {
                it.copy(
                    attempts = it.attempts + 1,
                    lastLatencyMs = result.latencyMs,
                    lastRequestBytes = result.requestBytes,
                    lastError = describe(result.error),
                    frameSize = sent.width to sent.height,
                    localizer = label,
                )
            }
            return
        }
        val fix = Fix(
            position = alignment.toGraph(Vec2(planar.x, planar.z)),
            heading = Geometry.wrapAngle(alignment.toGraphHeading(planar.heading)),
            atMillis = capturedAt,
            mapId = result.mapId,
        )
        _state.update {
            it.copy(
                attempts = it.attempts + 1,
                fixes = it.fixes + 1,
                lastLatencyMs = result.latencyMs,
                lastRequestBytes = result.requestBytes,
                lastError = null,
                lastFix = fix,
                frameSize = sent.width to sent.height,
                localizer = label,
            )
        }
        onFix?.invoke(fix)
    }

    companion object {
        const val MIN_INTERVAL_MS = 1000L
        const val SENT_WIDTH = 960
        const val MAX_FRAME_AGE_MS = 1500L

        /** Immersal's terse codes, worded for the screen (lessons from iOS field debugging). */
        fun describe(error: String): String = when {
            error == "none" -> "no match: frame not recognised"
            error == "auth" -> "auth: the token was refused"
            error == "map count" -> "map count: this token cannot see that map"
            ImmersalClient.isTransportFailure(error) -> "network: ${error.removePrefix("transport: ")}"
            else -> error
        }
    }
}
