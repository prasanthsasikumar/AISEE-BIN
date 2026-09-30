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
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.glasses.GlassesController
import com.flowsxr.aiseebin.glasses.Link
import com.flowsxr.aiseebin.glasses.Stream
import com.flowsxr.aiseebin.map.LocationDescriber
import com.flowsxr.aiseebin.ui.MapCanvas
import com.realsil.sdk.audioconnect.smartwear.live.view.RTKVideoView
import kotlin.math.roundToInt

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
            AiseeTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Screen(model, permissionsGranted,
                        requestPermissions = { permissionRequest.launch(requiredPermissions()) },
                        openBluetoothSettings = { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) })
                }
            }
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

@Composable
private fun AiseeTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) {
        darkColorScheme(primary = Color(0xFF7CC4A0), secondary = Color(0xFFB7D8C5))
    } else {
        lightColorScheme(primary = Color(0xFF2F6B4F), secondary = Color(0xFF4F7C66))
    }
    MaterialTheme(colorScheme = colors, content = content)
}

@Composable
private fun Screen(model: AppModel, permissionsGranted: Boolean, requestPermissions: () -> Unit, openBluetoothSettings: () -> Unit) {
    val g by model.glasses.state.collectAsStateWithLifecycle()
    val live = g.stream == Stream.STARTING || g.stream == Stream.PLAYING
    // Painted here too: with the SDK's SurfaceView on screen the Surface behind
    // this stopped drawing and the white window showed through.
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding()) {
        if (live) {
            // Fixed, not in the scrolling list: the SDK's video is a SurfaceView,
            // which mis-places itself inside a scrolling parent.
            LiveVideo(g.stream, g.fps)
            LiveMap(model)
        }
        ScrollingPanels(model, live, permissionsGranted, requestPermissions, openBluetoothSettings)
    }
}

@Composable
private fun LiveVideo(stream: Stream, fps: Int) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                RTKVideoView(ctx).apply {
                    // Composite the video above the window. Left behind it, the SurfaceView
                    // made Compose's window transparent well beyond its own bounds (a black
                    // or white screen around the video). Nothing is drawn over it, so the
                    // status line sits below.
                    setZOrderMediaOverlay(true)
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
    Text(
        if (stream == Stream.PLAYING) "Live · $fps fps" else "Starting… accept the Wi-Fi prompt",
        Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp,
    )
}

/** The live map right under the video: where the glasses put you, and in words. */
@Composable
private fun LiveMap(model: AppModel) {
    val p by model.positioning.state.collectAsStateWithLifecycle()
    val m by model.maps.collectAsStateWithLifecycle()
    val map = m.map ?: return
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MapCanvas(map, p.lastFix, height = 220.dp)
        val fix = p.lastFix
        Text(
            when {
                fix != null -> LocationDescriber(map).describe(fix.position, fix.heading) ?: map.name
                p.running -> "Looking for your position in ${map.name}…"
                else -> "${map.name} · start positioning below"
            },
            fontWeight = FontWeight.Medium,
        )
    }
    HorizontalDivider()
}

@Composable
private fun ScrollingPanels(model: AppModel, live: Boolean, permissionsGranted: Boolean,
                            requestPermissions: () -> Unit, openBluetoothSettings: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (!live) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("AISEE-BIN", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text("glasses prototype", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        if (!permissionsGranted) {
            Section("Permissions") {
                Text("Bluetooth, nearby-devices and location permission are needed to reach the glasses.")
                Button(onClick = requestPermissions) { Text("Grant permissions") }
            }
        }
        if (live) {
            PositioningSection(model, showMap = false)
            GlassesSection(model, openBluetoothSettings)
        } else {
            GlassesSection(model, openBluetoothSettings)
        }
        MapSection(model)
        if (!live) PositioningSection(model, showMap = true)
        FieldTestSection(model)
        SettingsSection(model)
        LogSection(model)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            content()
        }
    }
}

@Composable
private fun Row2(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun GlassesSection(model: AppModel, openBluetoothSettings: () -> Unit) {
    val g by model.glasses.state.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    Section("Glasses") {
        Row2("Status", when (g.link) {
            Link.DISCONNECTED -> "Not connected"
            Link.CONNECTING -> "Connecting…"
            Link.CONNECTED -> "Setting up…"
            Link.READY -> "Connected"
        })
        g.name?.let { Row2("Device", it) }
        g.battery?.let { Row2("Battery", "$it%") }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (g.link == Link.DISCONNECTED) {
                Button(onClick = { picking = !picking }) { Text("Connect…") }
            } else {
                OutlinedButton(onClick = { model.glasses.disconnect() }) { Text("Disconnect") }
            }
        }
        if (picking && g.link == Link.DISCONNECTED) {
            val devices = remember(picking) { model.glasses.bondedDevices() }
            if (devices.isEmpty()) {
                Text("No paired devices. Pair the glasses in Bluetooth settings first, then come back.")
            } else {
                Text("Paired devices:", color = MaterialTheme.colorScheme.onSurfaceVariant)
                devices.forEach { d ->
                    Text(
                        "${d.name}  ·  ${d.address}",
                        Modifier
                            .fillMaxWidth()
                            .clickable { picking = false; model.glasses.connect(d.address, d.name) }
                            .padding(vertical = 8.dp),
                        fontWeight = if (GlassesController.looksLikeGlasses(d.name)) FontWeight.SemiBold else FontWeight.Normal,
                    )
                }
            }
            TextButton(onClick = openBluetoothSettings) { Text("Open Bluetooth settings") }
        }

        if (g.link == Link.READY || g.link == Link.CONNECTED) {
            HorizontalDivider()
            Row2("Camera", when (g.stream) {
                Stream.OFF -> "Off"
                Stream.STARTING -> "Starting… (accept the Wi-Fi prompt)"
                Stream.PLAYING -> "Live · ${g.fps} fps"
                Stream.STOPPING -> "Stopping…"
            })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (g.stream == Stream.OFF) {
                    Button(onClick = { model.startCamera() }) { Text("Start camera") }
                } else {
                    OutlinedButton(onClick = { model.stopCamera() }) { Text("Stop camera") }
                }
            }
        }
        g.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun MapSection(model: AppModel) {
    val m by model.maps.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    Section("Map") {
        val selected = m.available.firstOrNull { it.slug == m.selectedSlug }
        Row2("Map", m.map?.name ?: selected?.name ?: "none")
        m.map?.let { map ->
            Row2("Places", "${map.pois.count { it.isNamed }} named, ${map.edges.size} paths")
            val ids = map.alignment?.mapIds.orEmpty()
            if (ids.isNotEmpty()) {
                Row2("Immersal map", ids.joinToString())
                Row2("On this phone", when {
                    m.downloading -> "Downloading…"
                    m.cached.size == ids.size -> "Yes (works offline)"
                    else -> "No (cloud only)"
                })
                if (m.cached.size < ids.size && !m.downloading) {
                    OutlinedButton(onClick = { model.downloadMaps() }) { Text("Download for offline use") }
                }
            }
        }
        if (m.offline) Text("Offline: using the copy saved on this phone.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        m.status?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { picking = !picking }) { Text("Choose map…") }
            TextButton(onClick = { model.refreshMaps() }) { Text("Refresh") }
        }
        if (picking) {
            m.available.forEach { s ->
                val ready = s.immersalMapIds.isNotEmpty()
                Text(
                    "${s.name}  ·  v${s.version}${if (ready) "" else "  ·  no Immersal"}",
                    Modifier
                        .fillMaxWidth()
                        .clickable(enabled = ready) { picking = false; model.selectMap(s.slug) }
                        .padding(vertical = 8.dp),
                    color = if (ready) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    fontWeight = if (s.slug == m.selectedSlug) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
private fun PositioningSection(model: AppModel, showMap: Boolean) {
    val p by model.positioning.state.collectAsStateWithLifecycle()
    val m by model.maps.collectAsStateWithLifecycle()
    val g by model.glasses.state.collectAsStateWithLifecycle()
    val spoken by model.spoken.collectAsStateWithLifecycle()
    val starting by model.starting.collectAsStateWithLifecycle()
    Section("Where am I") {
        val canStart = !m.map?.alignment?.mapIds.isNullOrEmpty() && g.stream == Stream.PLAYING && !starting
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!p.running) {
                Button(onClick = { model.startPositioning() }, enabled = canStart) { Text("Start positioning") }
            } else {
                OutlinedButton(onClick = { model.stopPositioning() }) { Text("Stop") }
            }
            Button(onClick = { model.whereAmI() }) { Text("Where am I?") }
        }
        if (!canStart && !p.running) {
            Text(
                when {
                    starting -> "Loading the map into the localizer…"
                    m.map?.alignment?.mapIds.isNullOrEmpty() -> "Pick a map with an Immersal alignment first."
                    else -> "Start the glasses camera first."
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        p.localizer?.let { Row2("Localizer", it) }
        if (p.running || p.attempts > 0) {
            Row2("Fixes", "${p.fixes} of ${p.attempts} tries" + if (p.rejected > 0) " · ${p.rejected} rejected" else "")
            p.lastLatencyMs?.let { Row2("Last try", "$it ms") }
            p.frameSize?.let { Row2("Frame sent", "${it.first}×${it.second}") }
            p.lastError?.let { Row2("Last result", it) }
        }
        p.lastFix?.let { fix ->
            val age = ((System.currentTimeMillis() - fix.atMillis) / 1000).toInt()
            Row2("Position", "x %.1f  z %.1f m".format(fix.position.x, fix.position.z))
            Row2("Heading", "${Math.toDegrees(fix.heading.toDouble()).roundToInt()}°")
            Row2("Fix age", "${age}s")
            m.map?.let { map -> LocationDescriber(map).describe(fix.position, fix.heading)?.let { Text(it, fontWeight = FontWeight.Medium) } }
        }
        spoken?.let { Text("Last spoken: $it", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp) }
        if (showMap) m.map?.let { MapCanvas(it, p.lastFix) }
        val announce by model.announcePlaces.collectAsStateWithLifecycle()
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Announce places as I walk")
                Text("Exhibits and hazards, within the radius set in the map editor.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            }
            Switch(checked = announce, onCheckedChange = model::setAnnouncePlaces)
        }
        Text("A glasses button press also asks \"where am I\".", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
    }
}

@Composable
private fun FieldTestSection(model: AppModel) {
    val m by model.maps.collectAsStateWithLifecycle()
    val checks by model.checks.collectAsStateWithLifecycle()
    val busy by model.fieldBusy.collectAsStateWithLifecycle()
    val p by model.positioning.state.collectAsStateWithLifecycle()
    Section("Field test") {
        Text("Stand on a marked point and tap I'm here: for 10 seconds the app records the glasses' positions and how far they are from the point. Results go to the team's server.",
            color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        val points = remember(m.map) { model.markedPoints() }
        if (m.map == null) Text("Load a map first.")
        else if (points.isEmpty()) Text("No points marked yet: mark them with the iPhone app's Field Test first.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        else if (!p.running) Text("Start positioning to check.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        points.forEach { poi ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(poi.name, fontWeight = FontWeight.Medium)
                    checks[poi.id]?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp) }
                }
                Button(onClick = { model.check(poi) }, enabled = busy == null && p.running) { Text("I'm here") }
            }
        }
        busy?.let { Text(it, fontWeight = FontWeight.Medium) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { model.reloadMap() }, enabled = busy == null) { Text("Reload map") }
            OutlinedButton(onClick = { model.sendLog() }, enabled = busy == null) { Text("Send log") }
        }
        Text("Reload map picks up points just marked on the iPhone; start positioning again afterwards.",
            color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
    }
}

@Composable
private fun SettingsSection(model: AppModel) {
    val focal by model.focalPx.collectAsStateWithLifecycle()
    val token by model.tokenOverride.collectAsStateWithLifecycle()
    var open by remember { mutableStateOf(false) }
    Section("Settings") {
        TextButton(onClick = { open = !open }) { Text(if (open) "Hide" else "Show") }
        if (open) {
            val mode by model.localizerMode.collectAsStateWithLifecycle()
            Text("Localization", fontWeight = FontWeight.Medium)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AppModel.LocalizerMode.entries.forEach { m ->
                    if (m == mode) Button(onClick = {}, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(m.label, fontSize = 13.sp) }
                    else OutlinedButton(onClick = { model.setLocalizerMode(m) }, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(m.label, fontSize = 13.sp) }
                }
            }
            Text("Auto uses the Immersal server when the phone has internet and the phone otherwise. On phone needs the map downloaded; Immersal server needs internet.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            HorizontalDivider()
            Row2("Lens focal length", "${focal.roundToInt()} px @1280")
            Slider(value = focal, onValueChange = { model.setFocal((it / 25).roundToInt() * 25f) }, valueRange = 600f..1400f)
            Text("1100 px was measured on iOS for these glasses. Takes effect on the next positioning start.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            OutlinedTextField(
                value = token,
                onValueChange = model::setTokenOverride,
                label = { Text("Immersal token") },
                placeholder = { Text(if (model.hasBuiltInToken) "Built in" else "Required") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row2("On-device localizer", if (model.nativeAvailable) "available" else "missing")
        }
    }
}

@Composable
private fun LogSection(model: AppModel) {
    val lines by model.log.collectAsStateWithLifecycle()
    var open by remember { mutableStateOf(false) }
    Section("Log") {
        TextButton(onClick = { open = !open }) { Text(if (open) "Hide (${lines.size})" else "Show (${lines.size})") }
        if (open) {
            lines.takeLast(60).reversed().forEach {
                Text(it, fontFamily = FontFamily.Monospace, fontSize = 11.sp, lineHeight = 14.sp)
            }
        }
    }
}
