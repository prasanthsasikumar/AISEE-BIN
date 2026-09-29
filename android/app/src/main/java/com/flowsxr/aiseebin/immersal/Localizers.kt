package com.flowsxr.aiseebin.immersal

import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** One way of turning a gray frame into a pose. Blocking; call off the main thread. */
interface Localizer {
    /** Shown on screen: "on-device" or "cloud". */
    val label: String
    fun localize(frame: GrayImage, k: GlassesCamera.Intrinsics): LocalizeResult
    fun close() {}
}

class CloudLocalizer(token: String, mapIds: List<Int>) : Localizer {
    private val client = ImmersalClient(token, mapIds)
    override val label = "cloud"
    override fun localize(frame: GrayImage, k: GlassesCamera.Intrinsics) = client.localize(frame.toPng(), k)
}

/**
 * Cloud when the phone's default network has working internet (fast: ~0.5 s a
 * fix on iOS), on-device otherwise — the usual case while the phone sits on
 * the glasses' Wi-Fi with no SIM data. A cloud call that fails on the network
 * is retried on-device with the same frame.
 */
class AutoLocalizer(
    private val cloud: CloudLocalizer?,
    private val native: NativeLocalizer?,
    private val hasInternet: () -> Boolean,
) : Localizer {
    @Volatile private var last = if (cloud != null) "cloud" else "on-device"
    override val label: String get() = "auto · $last"

    override fun localize(frame: GrayImage, k: GlassesCamera.Intrinsics): LocalizeResult {
        if (cloud != null && (native == null || hasInternet())) {
            val r = cloud.localize(frame, k)
            if (native == null || !ImmersalClient.isTransportFailure(r.error)) { last = "cloud"; return r }
        }
        if (native != null) { last = "on-device"; return native.localize(frame, k) }
        return LocalizeResult(false, "no localizer available", null, null, 0, 0)
    }

    override fun close() { native?.close() }
}

/**
 * Immersal's own native plugin (libPosePlugin.so from SDK 2.4.0, fetched at
 * build time; see app/build.gradle.kts) localizing against map files cached on
 * the phone: no network while the phone sits on the glasses' Wi-Fi, which has
 * no internet. Mirrors iOS `ImmersalNative`.
 */
class NativeLocalizer private constructor(private val handles: Map<Int, Int>) : Localizer {
    override val label = "on-device"
    private var closed = false

    override fun localize(frame: GrayImage, k: GlassesCamera.Intrinsics): LocalizeResult {
        val started = System.nanoTime()
        val out = FloatArray(8) // handle, px, py, pz, qx, qy, qz, qw
        synchronized(NativeLocalizer) {
            if (closed) return LocalizeResult(false, "localizer closed", null, null, 0, 0)
            ImmersalNative.localize(handles.values.toIntArray(), frame.width, frame.height,
                floatArrayOf(k.fx, k.fy, k.ox, k.oy), frame.pixels, out)
        }
        val ms = (System.nanoTime() - started) / 1_000_000
        val handle = out[0].toInt()
        val mapId = handles.entries.firstOrNull { it.value == handle }?.key
        if (handle < 0 || mapId == null) {
            return LocalizeResult(false, "none", null, null, ms, frame.pixels.size)
        }
        val pose = rawPose(out[1], out[2], out[3], out[4], out[5], out[6], out[7])
        return LocalizeResult(pose.isWellFormed, if (pose.isWellFormed) "none" else "malformed pose",
            mapId, pose, ms, frame.pixels.size)
    }

    override fun close() {
        synchronized(NativeLocalizer) {
            if (closed) return
            closed = true
            handles.values.forEach { ImmersalNative.freeMap(it) }
        }
    }

    companion object {
        private const val TAG = "NativeLocalizer"

        /** Loads every map, or returns null (with the reason) if the plugin or any map is missing. */
        fun open(mapIds: List<Int>, cache: ImmersalMapCache): Pair<NativeLocalizer?, String> {
            if (!ImmersalNative.available) return null to "native plugin not in this build"
            val handles = linkedMapOf<Int, Int>()
            synchronized(NativeLocalizer) {
                for (id in mapIds) {
                    val bytes = cache.bytes(id)
                    if (bytes == null) {
                        handles.values.forEach { ImmersalNative.freeMap(it) }
                        return null to "map $id not cached"
                    }
                    val h = ImmersalNative.loadMap(bytes)
                    if (h < 0) {
                        handles.values.forEach { ImmersalNative.freeMap(it) }
                        cache.delete(id)
                        return null to "map $id refused by the plugin"
                    }
                    handles[id] = h
                }
            }
            Log.i(TAG, "loaded maps $handles")
            return NativeLocalizer(handles) to "maps ${mapIds.joinToString()} loaded"
        }

        /** Quaternion → row-major r00…r22, as the REST response lists them (iOS `ImmersalNative.rawPose`). */
        fun rawPose(px: Float, py: Float, pz: Float, x: Float, y: Float, z: Float, w: Float): ImmersalRawPose {
            val r = floatArrayOf(
                1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
                2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
                2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
            )
            return ImmersalRawPose(px, py, pz, r)
        }
    }
}

/** JNI bridge to libaiseebin.so, which wraps libPosePlugin.so. */
object ImmersalNative {
    val available: Boolean = try {
        System.loadLibrary("aiseebin")
        nativeAvailable()
    } catch (e: Throwable) {
        Log.w("ImmersalNative", "native plugin unavailable: $e")
        false
    }

    @JvmStatic private external fun nativeAvailable(): Boolean
    @JvmStatic external fun setInteger(name: String, value: Int): Int
    @JvmStatic external fun loadMap(bytes: ByteArray): Int
    @JvmStatic external fun freeMap(handle: Int): Int
    @JvmStatic external fun localize(handles: IntArray, width: Int, height: Int, intrinsics: FloatArray,
                                     pixels: ByteArray, out: FloatArray)
}

/**
 * Map files on the phone, `files/immersal-maps/<id>.bytes`, fetched with
 * `GET /map?token&id` — token first, which Immersal's server requires, and
 * accepted by the LZMA magic byte because Immersal serves them as text/plain
 * (both learned on iOS, 2026-09-26).
 */
class ImmersalMapCache(root: File) {
    private val dir = File(root, "immersal-maps").apply { mkdirs() }

    fun has(id: Int) = file(id).length() > MIN_BYTES
    fun bytes(id: Int): ByteArray? = file(id).takeIf { it.length() > MIN_BYTES }?.readBytes()
    fun delete(id: Int) { file(id).delete() }
    fun cachedIds(): List<Int> = dir.listFiles()?.mapNotNull { it.name.removeSuffix(".bytes").toIntOrNull() }?.sorted().orEmpty()

    /** Downloads one map. Returns null on success, else why not. Blocking. */
    fun download(token: String, id: Int): String? {
        return try {
            val conn = (URL("https://api.immersal.com/map?token=$token&id=$id").openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 60_000
            }
            val status = conn.responseCode
            val body = (if (status in 200..299) conn.inputStream else conn.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
            conn.disconnect()
            when {
                status !in 200..299 -> "http $status: ${String(body.take(120).toByteArray())}"
                body.size <= MIN_BYTES || body[0] != 0x5d.toByte() -> "not a map: ${String(body.take(120).toByteArray())}"
                else -> {
                    val tmp = File(dir, "$id.tmp")
                    tmp.writeBytes(body)
                    tmp.renameTo(file(id))
                    null
                }
            }
        } catch (e: Exception) {
            "network: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    private fun file(id: Int) = File(dir, "$id.bytes")

    companion object { private const val MIN_BYTES = 1024L }
}
