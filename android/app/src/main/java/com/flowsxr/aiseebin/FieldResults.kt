package com.flowsxr.aiseebin

import android.os.Build
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Field-test results to the shared `ab_field_results` table, and logs to
 * storage, the same as the iPhone app: a test run on site can be read back the
 * same day. Blocking; call off the main thread.
 */
object FieldResults {
    private const val BASE = "https://djfpemdkeguztyuerxqc.supabase.co"
    private const val KEY = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"
    private const val BUCKET = "aiseebin-maps"

    val device: String get() = "${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE}"

    fun post(kind: String, mapSlug: String?, mode: String?, localizer: String?, pointId: String?, pointName: String?,
             payload: JSONObject) {
        val row = JSONObject().apply {
            put("kind", kind); put("platform", "android"); put("device", device)
            put("app_version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            put("map_slug", mapSlug); put("mode", mode); put("localizer", localizer)
            put("point_id", pointId); put("point_name", pointName); put("payload", payload)
        }
        send("$BASE/rest/v1/ab_field_results", "application/json", row.toString().toByteArray())
    }

    /** Uploads the diagnostics log and records where it went; returns the storage path. */
    fun uploadLog(file: File?, mapSlug: String?): String {
        val data = file?.takeIf { it.isFile }?.readBytes() ?: "empty log".toByteArray()
        val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
        val who = "${Build.MANUFACTURER}-${Build.MODEL}".replace(Regex("[^A-Za-z0-9]+"), "-")
        val path = "field-logs/${stamp.take(10)}/android-$who-$stamp.log"
        send("$BASE/storage/v1/object/$BUCKET/$path", "text/plain", data, upsert = true)
        post("log", mapSlug, null, null, null, null, JSONObject().put("path", path).put("bytes", data.size))
        return path
    }

    private fun send(url: String, type: String, body: ByteArray, upsert: Boolean = false) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"; doOutput = true; connectTimeout = 10_000; readTimeout = 30_000
            setRequestProperty("apikey", KEY)
            setRequestProperty("Authorization", "Bearer $KEY")   // as the iPhone app sends; storage uploads work with it
            setRequestProperty("Content-Type", type)
            if (upsert) setRequestProperty("x-upsert", "true")
            setFixedLengthStreamingMode(body.size)
        }
        try {
            conn.outputStream.use { it.write(body) }
            val status = conn.responseCode
            if (status !in 200..299) {
                val err = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                error("server answered $status ${err.take(160)}")
            }
        } finally { conn.disconnect() }
    }
}
