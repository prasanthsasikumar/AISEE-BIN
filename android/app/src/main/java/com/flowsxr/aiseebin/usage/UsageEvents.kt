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
