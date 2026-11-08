package com.flowsxr.aiseebin.usage

/**
 * Lets one pose through per [intervalMs]: the per-frame paths ask this before
 * building a `pose` event, so a 60 Hz camera costs one comparison per frame.
 * Called from the main thread (fixes) and the GL thread (ARCore frames).
 */
class PoseSampler(private val intervalMs: Long = 1000) {
    private var last: Long? = null

    @Synchronized
    fun shouldSample(atMs: Long): Boolean {
        val l = last
        if (l != null && atMs - l < intervalMs) return false
        last = atMs
        return true
    }

    @Synchronized
    fun reset() { last = null }
}
