package com.flowsxr.aiseebin.positioning

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat

/**
 * Metres walked since [start], for [FixGate]: the Android stand-in for iOS
 * `CMPedometer`. Uses the hardware step counter (the phone can be in a pocket)
 * at an assumed stride; without the sensor or its permission it allows walking
 * pace for the time elapsed, which still rejects the multi-metre jumps a wrong
 * fix makes between two one-second tries.
 */
class Odometer(context: Context) : SensorEventListener {
    private val app = context.applicationContext
    private val sensors = app.getSystemService(SensorManager::class.java)
    private val stepSensor: Sensor? = sensors?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    @Volatile private var baseSteps = -1f
    @Volatile private var steps = 0f
    @Volatile private var startedAt = 0L
    @Volatile var usingSteps = false
        private set

    val source: String get() = if (usingSteps) "step counter" else "walking-pace estimate"

    fun start() {
        stop()
        baseSteps = -1f
        steps = 0f
        startedAt = SystemClock.elapsedRealtime()
        val permitted = Build.VERSION.SDK_INT < 29 ||
            ContextCompat.checkSelfPermission(app, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        usingSteps = stepSensor != null && permitted &&
            sensors?.registerListener(this, stepSensor, SensorManager.SENSOR_DELAY_UI, 0) == true
    }

    fun stop() {
        sensors?.unregisterListener(this)
    }

    /** Metres walked since [start]. */
    val walked: Float
        get() = if (usingSteps) steps * STRIDE_M
        else (SystemClock.elapsedRealtime() - startedAt) / 1000f * WALKING_PACE_MPS

    override fun onSensorChanged(event: SensorEvent) {
        val total = event.values.firstOrNull() ?: return
        if (baseSteps < 0) baseSteps = total
        steps = (total - baseSteps).coerceAtLeast(0f)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    companion object {
        const val STRIDE_M = 0.7f
        const val WALKING_PACE_MPS = 1.4f
    }
}
