package com.flowsxr.aiseebin.glasses

import com.flowsxr.aiseebin.immersal.GrayImage
import com.flowsxr.aiseebin.immersal.ImmersalNative

/** A decoded frame with its sequence number and the wall-clock time it arrived. */
class TimedFrame(val image: GrayImage, val seq: Long, val capturedAtMillis: Long)

/**
 * Decoded glasses frames from Realtek's native player. Frames only flow once
 * the SDK's `RTKMediaPlayer` is playing the stream; registering early is fine.
 */
object GlassesFrames {
    init {
        // libaiseebin.so also holds the Immersal bridge; touching ImmersalNative loads it once.
        ImmersalNative.available
    }

    fun start() = nativeStart()
    fun stop() = nativeStop()

    /** Frames decoded since launch; the difference over a second is the fps. */
    val frameCount: Long get() = nativeFrameCount()

    /** Copy of the newest frame's luma plane, or null before the first frame. */
    fun latest(): TimedFrame? {
        val meta = IntArray(2)
        val stamp = LongArray(2)
        val bytes = nativeLatestLuma(meta, stamp) ?: return null
        return TimedFrame(GrayImage(meta[0], meta[1], bytes), stamp[0], stamp[1])
    }

    @JvmStatic private external fun nativeStart()
    @JvmStatic private external fun nativeStop()
    @JvmStatic private external fun nativeFrameCount(): Long
    @JvmStatic private external fun nativeLatestLuma(meta: IntArray, stamp: LongArray): ByteArray?
}
