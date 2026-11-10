package com.flowsxr.aiseebin.usage

import com.flowsxr.aiseebin.FieldResults
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** One `ab_sessions` row; [toJson] uses the column names. [startedAt] is epoch ms. */
data class SessionHeader(
    val sessionId: String,
    val installId: String,
    val platform: String,
    val device: String,
    val osVersion: String,
    val appVersion: String,
    val buildConfig: String,   // debug | release
    val simulator: Boolean,
    val staff: Boolean,
    val startedAt: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("session_id", sessionId).put("install_id", installId).put("app", "aiseebin").put("platform", platform)
        .put("device", device).put("os_version", osVersion).put("app_version", appVersion)
        .put("build_config", buildConfig).put("simulator", simulator).put("staff", staff)
        .put("started_at", UsageLog.timestamp(startedAt))

    companion object
}

/** Sends queued rows somewhere; throws to keep (or, per [UsageLog.isRejection], drop) the batch. */
interface UsageUploading {
    fun upload(sessions: List<JSONObject>, events: List<JSONObject>)
}

/** The server answered with a non-2xx status. */
class UsageHttpException(val status: Int, body: String) : IOException("server answered $status ${body.take(160)}")

/**
 * Posts headers, then events, to Supabase. Both tables are insert-only for the
 * publishable key, so a retried batch relies on `on_conflict` plus
 * `ignore-duplicates` (ON CONFLICT DO NOTHING) to drop rows already stored.
 * Blocking; [UsageLog] calls it off the main thread.
 */
class UsageUploader(
    private val open: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) : UsageUploading {

    override fun upload(sessions: List<JSONObject>, events: List<JSONObject>) {
        if (sessions.isNotEmpty()) post(sessions, "ab_sessions", "session_id")
        if (events.isNotEmpty()) post(events, "ab_events", "session_id,seq")
    }

    private fun post(rows: List<JSONObject>, table: String, conflict: String) {
        val body = JSONArray(rows).toString().toByteArray(Charsets.UTF_8)
        val conn = open(URL("${FieldResults.BASE}/rest/v1/$table?on_conflict=$conflict")).apply {
            requestMethod = "POST"; doOutput = true; connectTimeout = 10_000; readTimeout = 30_000
            setRequestProperty("apikey", FieldResults.KEY)
            setRequestProperty("Authorization", "Bearer ${FieldResults.KEY}")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Prefer", "resolution=ignore-duplicates,return=minimal")
            setFixedLengthStreamingMode(body.size)
        }
        try {
            conn.outputStream.use { it.write(body) }
            val status = conn.responseCode
            if (status !in 200..299) {
                val err = runCatching { conn.errorStream?.bufferedReader()?.use { it.readText() } }.getOrNull() ?: ""
                throw UsageHttpException(status, err)
            }
        } finally {
            conn.disconnect()
        }
    }
}
