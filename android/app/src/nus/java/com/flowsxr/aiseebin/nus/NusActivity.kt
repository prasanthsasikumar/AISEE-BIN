package com.flowsxr.aiseebin.nus

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.flowsxr.aiseebin.BuildConfig

class NusActivity : ComponentActivity() {
    private val model: NusModel by viewModels()
    private var cameraGranted by mutableStateOf(false)
    private var showPlaces by mutableStateOf(false)
    private var showStaff by mutableStateOf(false)
    private var showIntro by mutableStateOf(false)

    private val cameraRequest = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraGranted = granted
        model.append("camera permission: ${if (granted) "granted" else "refused"}")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Light screens throughout: dark icons in the status and navigation bars.
        enableEdgeToEdge(SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT), SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT))
        // A visitor walks with this open; keep the screen on while it is in front.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        cameraGranted = hasCamera()
        if (!cameraGranted) cameraRequest.launch(Manifest.permission.CAMERA)
        handleDebugCommand(intent)
        if (BuildConfig.DEBUG) {
            ContextCompat.registerReceiver(this, debugReceiver, IntentFilter(DEBUG_ACTION), ContextCompat.RECEIVER_EXPORTED)
        }
        setContent {
            NusRoot(model, cameraGranted,
                requestCamera = { cameraRequest.launch(Manifest.permission.CAMERA) },
                showPlaces = showPlaces, onShowPlaces = { showPlaces = it },
                showStaff = showStaff, onShowStaff = { showStaff = it },
                showIntro = showIntro, onShowIntro = { showIntro = it })
        }
    }

    override fun onResume() {
        super.onResume()
        // Granted in Settings while the app was away.
        cameraGranted = hasCamera()
    }

    override fun onPause() {
        model.cameraPaused()
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDebugCommand(intent)
    }

    override fun onDestroy() {
        if (BuildConfig.DEBUG) runCatching { unregisterReceiver(debugReceiver) }
        super.onDestroy()
    }

    private fun hasCamera() = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private val debugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = handleDebugCommand(intent)
    }

    /**
     * Debug builds only: drive the app over USB, e.g.
     * `adb shell am broadcast -a com.flowsxr.nusopenhouse.DEBUG -p com.flowsxr.nusopenhouse --es cmd standat --es id Entrance`
     * then `--es cmd tour`. `standat` needs the camera tracking; `fix` works without ARCore.
     */
    private fun handleDebugCommand(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val cmd = intent?.getStringExtra("cmd") ?: return
        model.append("debug command: $cmd")
        val id = intent.getStringExtra("id").orEmpty()
        when (cmd) {
            "tour" -> model.guide.startTour()
            "go" -> model.places.firstOrNull { it.id == id || it.name.equals(id, ignoreCase = true) }?.let(model.guide::goTo)
            "skip" -> model.guide.skipStop()
            "next" -> model.guide.nextStop()
            "exit" -> model.guide.exit()
            "places" -> showPlaces = true
            "staff" -> showStaff = true
            "intro" -> showIntro = true
            "voice" -> model.setVoice(intent.getStringExtra("on") != "false")
            "map" -> intent.getStringExtra("slug")?.let(model::switchMap)
            "standat" -> model.debugStandAt(id)
            "fix" -> model.debugFix(intent.getFloatExtra("x", 0f), intent.getFloatExtra("z", 0f),
                intent.getFloatExtra("h", 0f), intent.getFloatExtra("y", 0f))
        }
    }

    private companion object {
        const val DEBUG_ACTION = "com.flowsxr.nusopenhouse.DEBUG"
    }
}
