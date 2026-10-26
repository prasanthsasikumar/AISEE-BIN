package com.flowsxr.aiseebin

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * The Style Guide's haptic legend, as composed primitives where the phone has
 * them (API 30+ and supported) and waveforms of the same rhythm otherwise.
 */
class Haptics(context: Context) {
    private val vibrator = context.getSystemService(Vibrator::class.java)

    /** A light tap: staff-unlock taps 3–5. */
    fun tick() = play(listOf(PRIMITIVE_TICK to 0), longArrayOf(0, 12))
    /** A choice was taken. */
    fun confirm() = play(listOf(PRIMITIVE_CLICK to 0), longArrayOf(0, 30))
    /** Arrived: three rising taps. */
    fun arrival() = play(List(3) { PRIMITIVE_QUICK_RISE to if (it == 0) 0 else 90 }, longArrayOf(0, 40, 90, 60, 90, 90))
    /** Off route: three heavy taps. */
    fun offRoute() = play(List(3) { PRIMITIVE_THUD to if (it == 0) 0 else 120 }, longArrayOf(0, 120, 80, 120, 80, 120))

    private fun play(primitives: List<Pair<Int, Int>>, fallback: LongArray) {
        val v = vibrator ?: return
        runCatching {
            if (Build.VERSION.SDK_INT >= 30 && v.areAllPrimitivesSupported(*primitives.map { it.first }.toIntArray())) {
                val c = VibrationEffect.startComposition()
                primitives.forEach { (p, delay) -> c.addPrimitive(p, 1f, delay) }
                v.vibrate(c.compose())
            } else {
                v.vibrate(VibrationEffect.createWaveform(fallback, -1))
            }
        }
    }

    private companion object {
        // VibrationEffect.Composition constants, inlined so minSdk 26 compiles them.
        const val PRIMITIVE_CLICK = 1
        const val PRIMITIVE_THUD = 2
        const val PRIMITIVE_QUICK_RISE = 6
        const val PRIMITIVE_TICK = 7
    }
}
