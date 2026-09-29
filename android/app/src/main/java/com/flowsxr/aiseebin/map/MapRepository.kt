package com.flowsxr.aiseebin.map

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
)

/**
 * Reads published maps from the same Supabase table the iOS app and the web
 * editor use. Read-only: publishing stays on iPhone. The publishable key is
 * the one already shipped in the iOS app (`ServerConfig.publishableKey`).
 * Blocking; call off the main thread.
 */
object MapRepository {
    private const val BASE = "https://djfpemdkeguztyuerxqc.supabase.co/rest/v1/ab_map_versions"
    private const val KEY = "sb_publishable_hEk_pFTUws4X_SL7QKiFUA_DeFU9-YL"

    /** What came back, and whether it is the copy saved on the phone because the server was unreachable. */
    data class Loaded<T>(val value: T, val offline: Boolean)

    /**
     * Newest version of every map, sorted with glasses-ready maps first. The
     * answer is saved in [cacheDir] and served from there when the server is
     * unreachable — the usual case on the glasses' Wi-Fi with no SIM data.
     */
    fun list(cacheDir: File): Loaded<List<MapSummary>> {
        val select = "map_slug,version,name:graph->>name,alignment:graph->immersalAlignment"
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

    private fun parseList(rows: JSONArray): List<MapSummary> {
        val newest = linkedMapOf<String, MapSummary>()
        for (i in 0 until rows.length()) {
            val r = rows.getJSONObject(i)
            val slug = r.getString("map_slug")
            val version = r.getInt("version")
            if ((newest[slug]?.version ?: Int.MIN_VALUE) >= version) continue
            val ids = r.optJSONObject("alignment")?.optJSONArray("mapIDs")
            newest[slug] = MapSummary(
                slug = slug,
                name = r.optString("name").ifBlank { slug },
                version = version,
                immersalMapIds = ids?.let { a -> (0 until a.length()).map { a.getInt(it) } } ?: emptyList(),
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
