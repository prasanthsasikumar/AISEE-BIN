package com.flowsxr.aiseebin.usage

import org.json.JSONObject

/**
 * Payload builders shared by the instrumented classes, with the value
 * vocabularies the iOS app sends (`UsageInstrumentation.swift`).
 */

/** `settings.changed` data, or null when nothing changed. A secret logs only "set" or "empty". */
fun usageSetting(key: String, old: String, new: String, secret: Boolean = false): JSONObject? {
    fun shown(v: String) = if (secret) (if (v.isEmpty()) "empty" else "set") else v
    // A secret typed key by key stays "set": only empty <-> set is a change worth a row.
    if (shown(old) == shown(new)) return null
    return usageData("key" to key, "old" to shown(old), "new" to shown(new))
}

/** iOS localizer names: "on device" or "cloud", from Android's labels ("on-device", "auto · cloud"). */
fun usageLocalizerName(label: String): String = when {
    label.endsWith("cloud") -> "cloud"
    label.endsWith("on-device") -> "on device"
    else -> label
}

/**
 * `ar.tracking` state and reason from ARCore's `TrackingState` and
 * `TrackingFailureReason` names: normal | limited | not_available, the reason
 * in iOS wording (initializing, excessive_motion, insufficient_features, ...).
 */
fun usageArTracking(trackingState: String, failureReason: String?): Pair<String, String?> = when (trackingState) {
    "TRACKING" -> "normal" to null
    "PAUSED" -> "limited" to (if (failureReason == null || failureReason == "NONE") "initializing" else failureReason.lowercase())
    else -> "not_available" to null
}

/**
 * `pose` data in map-graph metres (cm-rounded), or null when there is no numeric
 * position: a pose is never logged without x and z (before the ARCore anchor
 * exists, `ar.tracking` covers that period).
 */
fun usagePose(x: Float?, z: Float?, heading: Float?, tracking: String, localized: Boolean): JSONObject? {
    if (x == null || z == null || !x.isFinite() || !z.isFinite()) return null
    return usageData("x" to Math.round(x * 100.0) / 100.0, "z" to Math.round(z * 100.0) / 100.0,
        "heading" to heading?.let { Math.round(it * 1000.0) / 1000.0 }, "tracking" to tracking, "localized" to localized)
}
