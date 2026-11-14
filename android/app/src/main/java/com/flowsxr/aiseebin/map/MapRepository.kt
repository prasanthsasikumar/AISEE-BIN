package com.flowsxr.aiseebin.map

import com.flowsxr.aiseebin.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class MapSummary(
    val slug: String,
    val name: String,
    val version: Int,
    /** Immersal map ids, empty when the map has no Immersal alignment (glasses cannot position in it). */
    val immersalMapIds: List<Int>,
    /** When this version was published (ISO 8601, sorts as text); "" in lists saved by older builds. */
    val createdAt: String = "",
)

/**
 * Reads published maps from the same Supabase table the iOS app and the web
 * editor use. Read-only: publishing stays on iPhone. The publishable key is
 * the one already shipped in the iOS app (`ServerConfig.publishableKey`).
 * Blocking; call off the main thread.
 */
object MapRepository {
    /** Maps for the NUS app are published as `nus-…`; that app lists only those and AISEE-BIN hides them (iOS `ServerConfig.lists`). */
    const val NUS_PREFIX = "nus-"
    /** The NUS app's map: NUS Computing from the Aria walk (iOS `nusDefaultSlug`). */
    const val NUS_DEFAULT_SLUG = "nus-computing"

    fun lists(slug: String, nusApp: Boolean = BuildConfig.NUS_APP) = slug.startsWith(NUS_PREFIX) == nusApp

    /** The NUS app's map on a phone with none: its default, else the most recently published `nus-` map. */
    fun nusStarterSlug(maps: List<MapSummary>): String? =
        maps.firstOrNull { it.slug == NUS_DEFAULT_SLUG }?.slug
            ?: maps.filter { lists(it.slug, nusApp = true) }.maxByOrNull { it.createdAt }?.slug

    private const val BASE = "https://djfpemdkeguztyuerxqc.supabase.co/rest/v1/ab_map_versions"
    private const val STORAGE = "https://djfpemdkeguztyuerxqc.supabase.co/storage/v1/object/public/aiseebin-maps"
    private const val KEY = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"

    /** What came back, and whether it is the copy saved on the phone because the server was unreachable. */
    data class Loaded<T>(val value: T, val offline: Boolean)

    /**
     * Newest version of every map, sorted with glasses-ready maps first. The
     * answer is saved in [cacheDir] and served from there when the server is
     * unreachable — the usual case on the glasses' Wi-Fi with no SIM data.
     */
    fun list(cacheDir: File): Loaded<List<MapSummary>> {
        val select = "map_slug,version,created_at,name:graph->>name,alignment:graph->immersalAlignment"
        val file = File(cacheDir.apply { mkdirs() }, "index.json")
        return try {
            val body = get("$BASE?select=${enc(select)}&order=map_slug.asc,version.desc")
            val list = parseList(JSONArray(body))
            runCatching { file.writeText(body) }
            Loaded(list, offline = false)
        } catch (e: Exception) {
            if (!file.isFile) throw e
            Loaded(parseList(JSONArray(file.readText())), offline = true)
        }
    }

    /** The newest version of [slug]; the saved copy when offline. */
    fun load(slug: String, cacheDir: File): Loaded<NavigationMap> {
        val file = File(cacheDir.apply { mkdirs() }, "${slug.replace(Regex("[^A-Za-z0-9_-]"), "_")}.json")
        return try {
            val graph = fetchGraph(slug)
            runCatching { file.writeText(graph.toString()) }
            Loaded(NavigationMap.parse(graph), offline = false)
        } catch (e: Exception) {
            if (!file.isFile) throw e
            Loaded(NavigationMap.parse(JSONObject(file.readText())), offline = true)
        }
    }

    internal fun parseList(rows: JSONArray, nusApp: Boolean = BuildConfig.NUS_APP): List<MapSummary> {
        val newest = linkedMapOf<String, MapSummary>()
        for (i in 0 until rows.length()) {
            val r = rows.getJSONObject(i)
            val slug = r.getString("map_slug")
            if (!lists(slug, nusApp)) continue
            val version = r.getInt("version")
            if ((newest[slug]?.version ?: Int.MIN_VALUE) >= version) continue
            val ids = r.optJSONObject("alignment")?.optJSONArray("mapIDs")
            newest[slug] = MapSummary(
                slug = slug,
                name = r.optString("name").ifBlank { slug },
                version = version,
                immersalMapIds = ids?.let { a -> (0 until a.length()).map { a.getInt(it) } } ?: emptyList(),
                createdAt = r.optString("created_at"),
            )
        }
        return newest.values.sortedWith(compareBy({ it.immersalMapIds.isEmpty() }, { it.name.lowercase() }))
    }

    private fun fetchGraph(slug: String): JSONObject {
        val url = "$BASE?select=graph&map_slug=eq.${enc(slug)}&order=version.desc&limit=1"
        val rows = JSONArray(get(url))
        require(rows.length() > 0) { "No map called $slug on the server" }
        return rows.getJSONObject(0).getJSONObject("graph")
    }

    /**
     * The scan's point cloud for the newest version of [slug]: x, y, z floats
     * in the graph frame, or null when the map has none. Downloaded once per
     * cloud and kept in [cacheDir]; the saved copy is used when offline.
     */
    fun loadPoints(slug: String, cacheDir: File): FloatArray? {
        val safe = slug.replace(Regex("[^A-Za-z0-9_-]"), "_")
        val file = File(cacheDir.apply { mkdirs() }, "$safe.points.f32")
        val which = File(cacheDir, "$safe.points.path")
        val path = try {
            val rows = JSONArray(get("$BASE?select=pointcloud_path&map_slug=eq.${enc(slug)}&order=version.desc&limit=1"))
            if (rows.length() == 0 || rows.getJSONObject(0).isNull("pointcloud_path")) return null
            rows.getJSONObject(0).getString("pointcloud_path")
        } catch (e: Exception) {
            if (!file.isFile) throw e
            null
        }
        if (path != null && !(file.isFile && which.isFile && which.readText() == path)) {
            val conn = (URL("$STORAGE/$path").openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 60_000
            }
            try {
                if (conn.responseCode !in 200..299) error("Point cloud download answered ${conn.responseCode}")
                val bytes = conn.inputStream.use { it.readBytes() }
                // Stored gzipped; the server may or may not have unpacked it already.
                val raw = if (bytes.size > 2 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte()) {
                    java.util.zip.GZIPInputStream(bytes.inputStream()).use { it.readBytes() }
                } else bytes
                file.writeBytes(raw)
                which.writeText(path)
            } finally {
                conn.disconnect()
            }
        }
        val raw = file.readBytes()
        val floats = FloatArray(raw.size / 4)
        java.nio.ByteBuffer.wrap(raw).order(java.nio.ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)
        return floats
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun get(url: String): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 20_000
            setRequestProperty("apikey", KEY)
        }
        try {
            val status = conn.responseCode
            val body = (if (status in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use { it.readText() } ?: ""
            if (status !in 200..299) error("Map server answered $status: ${body.take(200)}")
            return body
        } finally {
            conn.disconnect()
        }
    }
}
