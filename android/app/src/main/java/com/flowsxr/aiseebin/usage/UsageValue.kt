package com.flowsxr.aiseebin.usage

import org.json.JSONArray
import org.json.JSONObject

/**
 * Makes event payloads safe to store, as iOS `UsageValue` does: non-finite
 * numbers become JSON null, strings lose NUL characters (Postgres rejects them
 * in text and jsonb) and are cut to [MAX_STRING_LENGTH], so no payload can fail
 * to encode or balloon.
 */
object UsageValue {
    const val MAX_STRING_LENGTH = 4_000

    /** A cleaned copy: JSONObject/Map → JSONObject, JSONArray/Iterable/Array → JSONArray. */
    fun clean(value: Any?): Any = when (value) {
        null, JSONObject.NULL -> JSONObject.NULL
        is String -> cleanString(value)
        is Boolean -> value
        is Double -> if (value.isFinite()) value else JSONObject.NULL
        is Float -> if (value.isFinite()) value else JSONObject.NULL
        is Number -> value
        is JSONObject -> JSONObject().also { out ->
            value.keys().forEach { k -> out.put(cleanString(k), clean(value.opt(k))) }
        }
        is Map<*, *> -> JSONObject().also { out ->
            value.forEach { (k, v) -> out.put(cleanString(k.toString()), clean(v)) }
        }
        is JSONArray -> JSONArray().also { out -> for (i in 0 until value.length()) out.put(clean(value.opt(i))) }
        is Iterable<*> -> JSONArray().also { out -> value.forEach { out.put(clean(it)) } }
        is Array<*> -> JSONArray().also { out -> value.forEach { out.put(clean(it)) } }
        else -> cleanString(value.toString())
    }

    fun cleanString(s: String): String {
        val noNul = if (s.indexOf('\u0000') >= 0) s.replace("\u0000", "") else s
        return if (noNul.length > MAX_STRING_LENGTH) noNul.take(MAX_STRING_LENGTH) else noNul
    }
}

/**
 * Builds an event payload from pairs, e.g. `usageData("slug" to "x", "ms" to 12)`.
 * Unlike `JSONObject.put`, NaN and infinity are accepted (they become null).
 */
fun usageData(vararg pairs: Pair<String, Any?>): JSONObject =
    JSONObject().also { out -> pairs.forEach { (k, v) -> out.put(UsageValue.cleanString(k), UsageValue.clean(v)) } }
