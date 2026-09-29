package com.flowsxr.aiseebin.immersal

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.atan
import kotlin.math.atan2

/** The twelve numbers `/localizeb64` returns, as it returns them. */
data class ImmersalRawPose(val px: Float, val py: Float, val pz: Float, val r: FloatArray) {
    val isWellFormed: Boolean
        get() = r.size == 9 && r.all { it.isFinite() } && px.isFinite() && py.isFinite() && pz.isFinite()

    override fun equals(other: Any?): Boolean =
        other is ImmersalRawPose && px == other.px && py == other.py && pz == other.pz && r.contentEquals(other.r)

    override fun hashCode(): Int = 31 * (31 * (31 * px.hashCode() + py.hashCode()) + pz.hashCode()) + r.contentHashCode()
}

/** Camera position and heading on the floor plane of Immersal map space. */
data class PlanarPose(val x: Float, val z: Float, val heading: Float)

/**
 * Reads a raw pose the way iOS does (`ImmersalPoseConvention.rowMajorCVCamera`,
 * confirmed on a real walk 2026-09-15): `r` is row-major, and the camera is a
 * computer-vision camera (+Y down, +Z forward). So the camera's forward vector
 * in map space is the rotation's third column, (r02, r12, r22).
 *
 * Heading follows `NavigationGeometry`: heading h faces (sin h, -cos h) on (x, z).
 */
object ImmersalPose {
    fun planar(raw: ImmersalRawPose): PlanarPose? {
        if (!raw.isWellFormed) return null
        val fx = raw.r[2]
        val fz = raw.r[8]
        return PlanarPose(raw.px, raw.pz, atan2(fx, -fz))
    }
}

/**
 * Pinhole model for the uncalibrated glasses camera: principal point at the
 * image centre, one focal length for both axes, expressed at 1280 px wide and
 * scaled to the sent size. 1100 px is the value the iOS focal sweep measured
 * on these glasses (2026-09-16), about 60° horizontal.
 */
data class GlassesCamera(val focalPx: Float = DEFAULT_FOCAL_PX) {
    data class Intrinsics(val fx: Float, val fy: Float, val ox: Float, val oy: Float)

    fun intrinsics(width: Int, height: Int): Intrinsics {
        val f = focalPx * width / REFERENCE_WIDTH
        return Intrinsics(f, f, width / 2f, height / 2f)
    }

    val horizontalFovDegrees: Float
        get() = Math.toDegrees(2.0 * atan(REFERENCE_WIDTH / (2.0 * focalPx))).toFloat()

    companion object {
        const val REFERENCE_WIDTH = 1280f
        const val DEFAULT_FOCAL_PX = 1100f
    }
}

data class LocalizeResult(
    val success: Boolean,
    /** "none" on success, else Immersal's code (auth, query, map count, image) or a transport description. */
    val error: String,
    val mapId: Int?,
    val pose: ImmersalRawPose?,
    val latencyMs: Long,
    val requestBytes: Int,
)

/** Server-side localization, the same `/localizeb64` call iOS makes. Blocking; call off the main thread. */
class ImmersalClient(private val token: String, mapIds: List<Int>) {
    private val mapIds = mapIds.take(MAX_MAPS)

    fun localize(png: ByteArray, k: GlassesCamera.Intrinsics): LocalizeResult {
        val body = JSONObject().apply {
            put("token", token)
            put("mapIds", JSONArray().apply { mapIds.forEach { put(JSONObject().put("id", it)) } })
            put("b64", Base64.encodeToString(png, Base64.NO_WRAP))
            put("fx", k.fx.toDouble()); put("fy", k.fy.toDouble())
            put("ox", k.ox.toDouble()); put("oy", k.oy.toDouble())
        }.toString().toByteArray()

        val started = System.nanoTime()
        fun elapsed() = (System.nanoTime() - started) / 1_000_000
        val (status, text) = try {
            val conn = (URL(ENDPOINT).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 10_000
                readTimeout = 20_000
                setRequestProperty("Content-Type", "application/json")
                setFixedLengthStreamingMode(body.size)
            }
            conn.outputStream.use { it.write(body) }
            // Immersal reports a rejected request as HTTP 400 with the reason in
            // the body, so read the body whatever the status.
            val status = conn.responseCode
            val text = (if (status in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() } ?: ""
            conn.disconnect()
            status to text
        } catch (e: Exception) {
            return LocalizeResult(false, "transport: ${e.message ?: e.javaClass.simpleName}", null, null, elapsed(), body.size)
        }
        // Parsed outside the try: a malformed answer is Immersal's problem, not the network's,
        // and must not be retried on-device as if the request never arrived.
        return try {
            parse(text, status, elapsed(), body.size)
        } catch (e: Exception) {
            LocalizeResult(false, "http $status, bad body: ${e.message}", null, null, elapsed(), body.size)
        }
    }

    companion object {
        const val ENDPOINT = "https://api.immersal.com/localizeb64"
        const val MAX_MAPS = 8

        fun parse(text: String, status: Int, latencyMs: Long, requestBytes: Int): LocalizeResult {
            val json = try { JSONObject(text) } catch (e: Exception) {
                return LocalizeResult(false, "http $status, undecodable body", null, null, latencyMs, requestBytes)
            }
            val keys = listOf("r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22")
            val pose = if (json.has("px") && json.has("py") && json.has("pz") && keys.all { json.has(it) }) {
                ImmersalRawPose(
                    json.getDouble("px").toFloat(), json.getDouble("py").toFloat(), json.getDouble("pz").toFloat(),
                    FloatArray(9) { json.getDouble(keys[it]).toFloat() },
                )
            } else null
            val error = json.optString("error", "")
            val ok = json.optBoolean("success", false) && error == "none" && pose != null
            val mapId = if (json.has("map")) json.optInt("map") else null
            return LocalizeResult(ok, error.ifEmpty { if (ok) "none" else "missing error field" },
                mapId, pose, latencyMs, requestBytes)
        }

        fun isTransportFailure(error: String) = error.startsWith("transport:")
    }
}
