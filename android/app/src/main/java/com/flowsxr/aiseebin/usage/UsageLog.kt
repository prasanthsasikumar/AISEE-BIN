package com.flowsxr.aiseebin.usage

import android.content.Context
import android.os.Build
import android.util.Log
import com.flowsxr.aiseebin.BuildConfig
import com.flowsxr.aiseebin.FieldResults
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** The app's usage log, set up in `AiseeApp.onCreate` (main process only). */
object Usage {
    lateinit var log: UsageLog

    /** Fire-and-forget `log`, safe where the log may not exist (a non-main process, a unit test). */
    fun record(type: String, data: JSONObject = JSONObject()) {
        if (::log.isInitialized) log.log(type, data)
    }

    /** Sets (or with null clears) [UsageLog.onNewSession], if the log exists. */
    fun onNewSession(hook: (() -> Unit)?) {
        if (::log.isInitialized) log.onNewSession = hook
    }
}

/**
 * Records what happens in the app as numbered events per session and uploads
 * them to `ab_sessions` / `ab_events` in batches; the Android twin of iOS
 * `UsageLog`, writing the same rows.
 *
 * A session runs from launch to background; coming back after more than
 * [SESSION_TIMEOUT_MS] in the background starts a new one. Each session's
 * events are numbered from 0. Every call is fire-and-forget: state and disk I/O
 * run on [executor] (serial); uploads run on [uploadExecutor], one drain at a
 * time, touching the queue file only through short tasks on [executor], so a
 * slow upload never holds up logging. Nothing throws to callers.
 *
 * Never logs into `AppModel.append`: that log mirrors into this one, so its own
 * errors go to [android.util.Log] instead.
 *
 * @param header describes the first session; later sessions copy it with a
 *   fresh id and start time, and [staff] (when given) as it is then.
 * @param executor must run tasks one at a time, in order.
 * @param uploadExecutor must run tasks one at a time, in order; it waits on
 *   [executor], so never pass the same single thread for both.
 */
class UsageLog(
    dir: File,
    private val uploader: UsageUploading,
    private val now: () -> Long,
    header: SessionHeader,
    private val executor: Executor,
    private val maxQueueLines: Int = MAX_QUEUE_LINES,
    private val uploadExecutor: Executor =
        Executors.newSingleThreadExecutor { Thread(it, "usage-upload").apply { isDaemon = true } },
    private val staff: (() -> Boolean)? = null,
    onCompact: (() -> Unit)? = null,
) {
    companion object {
        const val SESSION_TIMEOUT_MS = 300_000L
        const val BATCH_SIZE = 500
        const val FLUSH_INTERVAL_MS = 30_000L
        /** Queue lines kept while uploads fail; older lines are dropped past this.
         *  With positioning running the app logs about 2.7 lines a second (pose,
         *  loc.attempt, diag, speech), so this is about 20 hours, a few tens of MB. */
        const val MAX_QUEUE_LINES = 200_000
        private const val TAG = "UsageLog"

        private val formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .withZone(ZoneOffset.UTC)

        /** ISO 8601, UTC, milliseconds: `2026-11-07T08:00:00.000Z`. */
        fun timestamp(epochMs: Long): String = formatter.format(Instant.ofEpochMilli(epochMs))

        /** A 4xx other than 408/429: the server refuses this batch and always will.
         *  No network, 5xx, timeouts and rate limits are worth retrying. */
        fun isRejection(e: Throwable): Boolean =
            e is UsageHttpException && e.status in 400..499 && e.status != 408 && e.status != 429
    }

    private val store = UsageQueue(dir, onCompact)
    private val marker = File(dir, "running")

    // Touched only on `executor`.
    private val template = header
    private var session = header
    private var headerQueued = false
    private var nextSeq = 0
    private var foregroundSince = now()
    private var backgroundSince: Long? = null
    private var timer: ScheduledExecutorService? = null

    /**
     * Called when coming back from a long background has started a new session,
     * right after its `app.foreground` is recorded, on the thread that called
     * [onForeground] (the main thread in the app). The app re-logs what the new
     * session would otherwise not know: the map, the mode and any positioning
     * run. Set it before the first foreground.
     */
    @Volatile var onNewSession: (() -> Unit)? = null

    /** The current session's id. Waits for queued work; not for hot paths. */
    val sessionId: String get() = sync(executor) { session.sessionId }

    fun log(type: String, data: JSONObject = JSONObject()) {
        val t = now()
        val clean = try {
            UsageValue.clean(data) as JSONObject
        } catch (e: Exception) {
            Log.e(TAG, "usage payload for $type unusable: $e"); JSONObject()
        }
        async { record(type, clean, t) }
    }

    /** Call once at app start, before anything else logs: `app.launch` is seq 0. */
    fun onLaunch() {
        val t = now()
        async {
            val previous = runCatching { marker.takeIf { it.isFile }?.readText()?.trim() }.getOrNull()
            foregroundSince = t
            backgroundSince = null
            writeMarker()
            record("app.launch", JSONObject().put("unclean_previous", previous ?: JSONObject.NULL), t)
            startTimer()
        }
        flush()
    }

    /** Logs `app.foreground` after a real trip to the background (the first start
     *  at launch is not one), starting a new session after a long one; then
     *  [onNewSession] runs. Waits for [executor] (a few file writes), so the
     *  hook's events follow `app.foreground` directly. */
    fun onForeground() {
        val t = now()
        val started = try {
            sync(executor) {
                var started = false
                backgroundSince?.let { since ->
                    if (t - since > SESSION_TIMEOUT_MS) { startSession(t); started = true }
                    foregroundSince = t
                    backgroundSince = null
                    record("app.foreground", JSONObject(), t)
                }
                writeMarker()
                startTimer()
                started
            }
        } catch (e: Exception) { Log.e(TAG, "usage foreground failed: $e"); false }
        if (started) try { onNewSession?.invoke() } catch (e: Exception) { Log.e(TAG, "usage new-session hook failed: $e") }
    }

    fun onBackground() {
        val t = now()
        async {
            if (backgroundSince != null) return@async
            record("app.background", JSONObject().put("seconds_active", Math.round((t - foregroundSince) / 1000.0)), t)
            backgroundSince = t
            stopTimer()
            marker.delete()
        }
        flush()
    }

    /** Uploads everything queued so far, oldest first, in the background. */
    fun flush() = async(uploadExecutor) { drain() }

    /** Uploads everything queued so far and waits. Not from the main thread or either executor. */
    fun flushBlocking() = sync(uploadExecutor) { drain() }

    // On `executor`.

    private fun record(type: String, data: JSONObject, t: Long) {
        if (!headerQueued) {
            append(JSONObject().put("session", session.toJson()))
            headerQueued = true
        }
        append(JSONObject().put("event", JSONObject()
            .put("session_id", session.sessionId).put("seq", nextSeq).put("t", timestamp(t))
            .put("type", type).put("data", data)))
        nextSeq += 1
    }

    private fun startSession(t: Long) {
        session = template.copy(sessionId = UUID.randomUUID().toString(), startedAt = t,
            staff = staff?.invoke() ?: template.staff)
        headerQueued = false
        nextSeq = 0
    }

    private fun append(line: JSONObject) {
        try { store.append(line.toString()) } catch (e: Exception) { Log.e(TAG, "usage queue append failed: $e") }
    }

    private fun writeMarker() {
        try {
            marker.parentFile?.mkdirs()
            marker.writeText(session.sessionId)
        } catch (e: Exception) { Log.e(TAG, "usage marker write failed: $e") }
    }

    private fun startTimer() {
        if (timer != null) return
        timer = Executors.newSingleThreadScheduledExecutor { Thread(it, "usage-timer").apply { isDaemon = true } }
            .also { it.scheduleWithFixedDelay({ flush() }, FLUSH_INTERVAL_MS, FLUSH_INTERVAL_MS, TimeUnit.MILLISECONDS) }
    }

    private fun stopTimer() {
        timer?.shutdownNow()
        timer = null
    }

    // On `uploadExecutor`. Queue access goes through `sync(executor)`; between
    // peek and drop, new lines only go to the end, so dropping the first
    // `batch.size` lines removes exactly the uploaded ones.

    private fun drain() {
        try {
            val dropped = sync(executor) { store.trim(maxQueueLines) }
            if (dropped > 0) Log.e(TAG, "usage queue over cap, dropped $dropped oldest lines")
        } catch (e: Exception) { Log.e(TAG, "usage queue trim failed: $e") }
        while (true) {
            val batch = try { sync(executor) { store.peekBatch(BATCH_SIZE) } } catch (e: Exception) {
                Log.e(TAG, "usage queue read failed: $e"); return
            }
            if (batch.isEmpty()) return
            val sessions = mutableListOf<JSONObject>()
            val events = mutableListOf<JSONObject>()
            for (text in batch) {
                val line = try { JSONObject(text) } catch (e: Exception) {
                    Log.e(TAG, "usage queue: dropping unreadable line"); continue
                }
                line.optJSONObject("session")?.let { sessions += it }
                line.optJSONObject("event")?.let { events += it }
            }
            try {
                uploader.upload(sessions, events)
            } catch (e: Exception) {
                if (isRejection(e)) {
                    // Retrying would fail the same way and block every later line.
                    Log.e(TAG, "usage upload rejected, dropping ${batch.size} lines: $e")
                } else {
                    Log.e(TAG, "usage upload failed, keeping ${batch.size} lines: $e")
                    return
                }
            }
            try { sync(executor) { store.drop(batch.size) } } catch (e: Exception) {
                Log.e(TAG, "usage queue drop failed: $e"); return
            }
            if (batch.size < BATCH_SIZE) return
        }
    }

    // Scheduling.

    private fun async(on: Executor = executor, block: () -> Unit) {
        try {
            on.execute {
                try { block() } catch (e: Exception) { Log.e(TAG, "usage task failed: $e") }
            }
        } catch (e: Exception) { Log.e(TAG, "usage task not scheduled: $e") }
    }

    /** Runs [block] on [on] after everything already scheduled there and waits for it. */
    private fun <T> sync(on: Executor, block: () -> T): T {
        val latch = CountDownLatch(1)
        var result: Result<T>? = null
        try {
            on.execute {
                result = runCatching(block)
                latch.countDown()
            }
        } catch (e: Exception) {
            result = Result.failure(e); latch.countDown()
        }
        latch.await()
        return result!!.getOrThrow()
    }
}

/** The app's preferences file and its staff-mode switch (`AppModel.staff`). */
const val APP_PREFS = "app"
const val KEY_STAFF = "staff.mode"

/** Staff mode as last saved; read when a session starts. */
fun storedStaff(context: Context): Boolean =
    context.getSharedPreferences(APP_PREFS, Context.MODE_PRIVATE).getBoolean(KEY_STAFF, false)

/** This device and build, starting now with a fresh session id. */
fun SessionHeader.Companion.current(context: Context): SessionHeader {
    val prefs = context.getSharedPreferences(APP_PREFS, Context.MODE_PRIVATE)
    val installId = prefs.getString("usage.installID", null) ?: UUID.randomUUID().toString().also {
        prefs.edit().putString("usage.installID", it).apply()
    }
    return SessionHeader(
        sessionId = UUID.randomUUID().toString(), installId = installId, platform = "android",
        device = FieldResults.device, osVersion = Build.VERSION.RELEASE,
        appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        buildConfig = if (BuildConfig.DEBUG) "debug" else "release",
        simulator = Build.FINGERPRINT.contains("generic") || Build.PRODUCT.contains("sdk"),
        staff = storedStaff(context), startedAt = System.currentTimeMillis(),
    )
}
