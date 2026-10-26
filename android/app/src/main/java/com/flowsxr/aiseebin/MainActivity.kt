package com.flowsxr.aiseebin

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.flowsxr.aiseebin.glasses.GlassesController
import com.flowsxr.aiseebin.ui.AppRoot

private const val DEBUG_ACTION = "com.flowsxr.aiseebin.DEBUG"

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    private var permissionsGranted by mutableStateOf(false)

    private val permissionRequest = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permissionsGranted = missingPermissions().isEmpty()
        model.append("permissions: ${if (permissionsGranted) "granted" else "missing ${missingPermissions()}"}")
        if (permissionsGranted) model.glasses.reconnectLast()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A tester walks with this open; keep the screen on while it is in front.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        permissionsGranted = missingPermissions().isEmpty()
        // Ask for everything not yet granted, including the optional step counter.
        val ungranted = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (ungranted.isNotEmpty()) permissionRequest.launch(ungranted.toTypedArray())
        handleDebugCommand(intent)
        if (BuildConfig.DEBUG) {
            ContextCompat.registerReceiver(this, debugReceiver, IntentFilter(DEBUG_ACTION), ContextCompat.RECEIVER_EXPORTED)
        }
        setContent {
            AppRoot(model, permissionsGranted,
                requestPermissions = { permissionRequest.launch(requiredPermissions()) },
                openBluetoothSettings = { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) },
                close = ::finish)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDebugCommand(intent)
    }

    override fun onDestroy() {
        if (BuildConfig.DEBUG) runCatching { unregisterReceiver(debugReceiver) }
        super.onDestroy()
    }

    private val debugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = handleDebugCommand(intent)
    }

    /**
     * Debug builds only: drive the app over USB without the screen, even while
     * the phone is locked, e.g.
     * `adb shell am broadcast -a com.flowsxr.aiseebin.DEBUG -p com.flowsxr.aiseebin --es cmd connect`.
     */
    private fun handleDebugCommand(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val cmd = intent?.getStringExtra("cmd") ?: return
        model.append("debug command: $cmd")
        when (cmd) {
            "devices" -> model.glasses.bondedDevices().forEach { model.append("bonded: ${it.name} ${it.address}") }
            "connect" -> model.glasses.bondedDevices().firstOrNull { GlassesController.looksLikeGlasses(it.name) }
                ?.let { model.glasses.connect(it.address, it.name) } ?: model.append("no glasses-like bonded device")
            "disconnect" -> model.glasses.disconnect()
            "camera" -> model.startCamera()
            "stopcamera" -> model.stopCamera()
            "position" -> model.startPositioning()
            "stopposition" -> model.stopPositioning()
            "whereami" -> model.whereAmI("adb")
            "eis" -> {
                val e = com.realsil.sdk.audioconnect.smartwear.SmartWearDeviceInfo.getInstance().eisParams
                model.append(if (e == null) "eis: none received" else
                    "eis: imuHz=${e.mImuRateHz} stab=${e.mEnableStabilization}/${e.mStabilization} crop=${e.mCropRatioMin}..${e.mCropRatioMax} " +
                        "rs=${e.mRsReadoutTimeMs}ms rms=${e.mRmsError} K=${e.mCameraMatrix?.joinToString()} D=${e.mDistortionCoeffs?.joinToString()}")
                val info = com.realsil.sdk.audioconnect.smartwear.SmartWearDeviceInfo.getInstance()
                model.append("sensors: camera=${runCatching { info.cameraStatus }.getOrNull()} gSensor=${runCatching { info.gSensorStatus }.getOrNull()}")
            }
            "fakefix" -> model.injectFix(intent.getFloatExtra("x", 0f), intent.getFloatExtra("z", 0f), intent.getFloatExtra("h", 0f))
            "fakeframes" -> model.fakeFrames(intent.getStringExtra("pattern"))
            "selftest" -> model.selfTest(intent.getStringExtra("pattern") ?: "checker")
            "setint" -> model.append("setInteger ${intent.getStringExtra("name")}=${intent.getIntExtra("value", 0)} → " +
                com.flowsxr.aiseebin.immersal.ImmersalNative.setInteger(intent.getStringExtra("name") ?: "", intent.getIntExtra("value", 0)))
            "map" -> intent.getStringExtra("slug")?.let(model::selectMap)
            "staff" -> model.setStaff(intent.getStringExtra("on") != "false")
        }
    }

    private fun requiredPermissions(): Array<String> = buildList {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (Build.VERSION.SDK_INT >= 29) add(Manifest.permission.ACTIVITY_RECOGNITION)
        if (Build.VERSION.SDK_INT >= 31) {
            add(Manifest.permission.BLUETOOTH_CONNECT)
            add(Manifest.permission.BLUETOOTH_SCAN)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            add(Manifest.permission.NEARBY_WIFI_DEVICES)
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    // Step counting is optional: without it the jump filter allows walking pace instead.
    private fun missingPermissions() = requiredPermissions().filter {
        it != Manifest.permission.ACTIVITY_RECOGNITION &&
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
    }
}

