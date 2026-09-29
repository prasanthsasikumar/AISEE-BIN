package com.flowsxr.aiseebin.map

import org.json.JSONArray
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

    /** Newest version of every map, sorted with glasses-ready maps first. */
    fun list(): List<MapSummary> {
        val select = "map_slug,version,name:graph->>name,alignment:graph->immersalAlignment"
        val rows = JSONArray(get("$BASE?select=${enc(select)}&order=map_slug.asc,version.desc"))
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

    fun load(slug: String): NavigationMap {
        val url = "$BASE?select=graph&map_slug=eq.${enc(slug)}&order=version.desc&limit=1"
        val rows = JSONArray(get(url))
        require(rows.length() > 0) { "No map called $slug on the server" }
        return NavigationMap.parse(rows.getJSONObject(0).getJSONObject("graph"))
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
