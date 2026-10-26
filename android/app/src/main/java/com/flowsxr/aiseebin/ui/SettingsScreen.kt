package com.flowsxr.aiseebin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.AppModel
import com.flowsxr.aiseebin.glasses.GlassesController
import com.flowsxr.aiseebin.glasses.Link
import com.flowsxr.aiseebin.glasses.Stream
import com.flowsxr.aiseebin.map.LocationDescriber
import kotlin.math.roundToInt

/** An M3 switch with a check thumb, in the AiSee green. */
@Composable
fun AiseeSwitch(checked: Boolean, onChange: (Boolean) -> Unit) = Switch(
    checked = checked, onCheckedChange = onChange,
    thumbContent = if (checked) { { Icon(Icons.Filled.Check, null, Modifier.size(SwitchDefaults.IconSize)) } } else null,
    colors = SwitchDefaults.colors(checkedTrackColor = Ink.SwitchOn, checkedIconColor = Ink.SwitchOn, checkedThumbColor = Color.White),
)

/** The scrolling body every staff screen shares. */
@Composable
private fun StaffPage(header: @Composable () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(Ink.Paper)) {
        header()
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) { content() }
    }
}

/**
 * Design H, split by audience. Visitors see only their own group and the
 * glasses; staff also get This phone and Developer.
 */
@Composable
fun SettingsScreen(model: AppModel, staff: Boolean, onDone: () -> Unit, onDeveloper: () -> Unit, onExitStaff: () -> Unit, openBluetoothSettings: () -> Unit) {
    val announce by model.announcePlaces.collectAsStateWithLifecycle()
    val visitor by model.visitorMode.collectAsStateWithLifecycle()
    StaffPage(header = {
        StaffHeader("Settings", null, onLogo = null) { TextAction("Done", onClick = onDone) }
    }) {
        GroupLabel("Visitor experience")
        StaffCard(padding = 0.dp) {
            SettingRow("Announce places", "Exhibits and hazards as you walk past, within the radius set in the map editor.") {
                AiseeSwitch(announce, model::setAnnouncePlaces)
            }
        }
        GroupLabel("Find my position with", Modifier.padding(top = 6.dp))
        SourceCard(model)
        GroupLabel("Smart glasses", Modifier.padding(top = 6.dp))
        GlassesCard(model, openBluetoothSettings)
        if (staff) {
            GroupLabel("This phone", Modifier.padding(top = 6.dp))
            StaffCard {
                Text("Visitors see", style = plex(500, 17, color = Ink.Text))
                Segmented(
                    listOf("Navigate", "Explore"),
                    selected = if (visitor == AppModel.VisitorMode.EXPLORE) 1 else 0,
                    enabled = listOf(true, false),
                ) { model.setVisitorMode(if (it == 1) AppModel.VisitorMode.EXPLORE else AppModel.VisitorMode.NAVIGATE) }
                Text("Explore is coming to Android.", style = plex(400, 13, color = Ink.Muted))
                StaffButton("Exit staff mode", StaffButtonStyle.PLAIN, Modifier.fillMaxWidth().heightIn(min = 52.dp), onClick = onExitStaff)
            }
            StaffCard(padding = 0.dp, modifier = Modifier.padding(top = 10.dp)) {
                SettingRow("Developer", "Immersal token · map ids · tests", onClick = onDeveloper) {
                    Icon(AiseeIcons.ChevronRight, null, Modifier.size(20.dp), tint = Ink.Muted)
                }
            }
        }
    }
}

@Composable
private fun SourceCard(model: AppModel) {
    val source by model.source.collectAsStateWithLifecycle()
    val ar by model.ar.support.collectAsStateWithLifecycle()
    val sources = AppModel.PositionSource.entries
    StaffCard {
        Segmented(sources.map { it.label }, sources.indexOf(source),
            sources.map { it != AppModel.PositionSource.PHONE || ar == com.flowsxr.aiseebin.phone.ArSupport.SUPPORTED }) {
            model.setSource(sources[it])
        }
        Text(when {
            ar == com.flowsxr.aiseebin.phone.ArSupport.UNSUPPORTED -> "This phone can't track itself (no ARCore), so the glasses are used."
            source == AppModel.PositionSource.PHONE -> "Hold the phone up: its camera recognises the space, as on iPhone. Keep the app open."
            else -> "The glasses' camera recognises the space; the phone can stay in a pocket."
        }, style = plex(400, 13, 1.4f, color = Ink.Muted))
    }
}

@Composable
private fun Segmented(labels: List<String>, selected: Int, enabled: List<Boolean>, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().background(Ink.Chip, RoundedCornerShape(14.dp)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        labels.forEachIndexed { i, label ->
            val on = i == selected
            Row(
                Modifier.weight(1f).heightIn(min = 44.dp)
                    .background(if (on) Ink.Text else Color.Transparent, RoundedCornerShape(11.dp))
                    .clickable(enabled = enabled[i] && !on, role = Role.RadioButton) { onSelect(i) },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, style = plex(if (on) 600 else 500, 16, color = when { on -> Color.White; enabled[i] -> Ink.Body; else -> Ink.Faint.copy(alpha = 0.6f) }))
            }
        }
    }
}

/** Glasses: link, battery, camera, and the paired-device picker. */
@Composable
fun GlassesCard(model: AppModel, openBluetoothSettings: () -> Unit) {
    val g by model.glasses.state.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    StaffCard(padding = 0.dp) {
        SettingRow("Glasses", g.name, divider = true) {
            Text(when (g.link) {
                Link.DISCONNECTED -> "Not connected"
                Link.CONNECTING -> "Connecting…"
                Link.CONNECTED -> "Setting up…"
                Link.READY -> g.battery?.let { "Connected · $it%" } ?: "Connected"
            }, style = plex(400, 16, color = Ink.Muted))
        }
        if (g.link == Link.READY || g.link == Link.CONNECTED) {
            SettingRow("Camera", divider = true) {
                Text(when (g.stream) {
                    Stream.OFF -> "Off"
                    Stream.STARTING -> "Starting…"
                    Stream.PLAYING -> "Live · ${g.fps} fps"
                    Stream.STOPPING -> "Stopping…"
                }, style = plex(400, 16, color = Ink.Muted))
            }
        }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (g.link == Link.DISCONNECTED) {
                    StaffButton("Connect…", StaffButtonStyle.PRIMARY, Modifier.weight(1f)) { picking = !picking }
                } else {
                    StaffButton("Disconnect", StaffButtonStyle.PLAIN, Modifier.weight(1f)) { model.glasses.disconnect() }
                }
                if (g.link == Link.READY || g.link == Link.CONNECTED) {
                    if (g.stream == Stream.OFF) StaffButton("Start camera", StaffButtonStyle.DARK, Modifier.weight(1f)) { model.startCamera() }
                    else StaffButton("Stop camera", StaffButtonStyle.PLAIN, Modifier.weight(1f)) { model.stopCamera() }
                }
            }
            if (g.stream == Stream.STARTING) Text("Tap Connect on Android's Wi-Fi prompt.", style = plex(400, 14, 1.4f, color = Ink.Muted))
            if (picking && g.link == Link.DISCONNECTED) {
                val devices = remember(picking) { model.glasses.bondedDevices() }
                if (devices.isEmpty()) {
                    Text("No paired devices. Pair the glasses (AiSee-G1_…) in Bluetooth settings first, then come back.", style = plex(400, 15, 1.4f, color = Ink.Body))
                } else {
                    devices.forEach { d ->
                        val likely = GlassesController.looksLikeGlasses(d.name)
                        Text(
                            "${d.name}  ·  ${d.address}",
                            Modifier.fillMaxWidth().clickable(role = Role.Button) { picking = false; model.glasses.connect(d.address, d.name) }.padding(vertical = 10.dp),
                            style = plex(if (likely) 600 else 400, 16, color = Ink.Text),
                        )
                    }
                }
                TextAction("Open Bluetooth settings", onClick = openBluetoothSettings)
            }
            g.error?.let { Text(it, style = plex(400, 14, 1.4f, color = Ink.Error)) }
            Text("A press of the glasses' button asks \"where am I\".", style = plex(400, 13, 1.4f, color = Ink.Muted))
        }
    }
}

/** Developer: everything the prototype screen had for testing, one level down. */
@Composable
fun DeveloperScreen(model: AppModel, onBack: () -> Unit) {
    StaffPage(header = {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 16.dp, top = 18.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", Modifier.size(48.dp).clickable(role = Role.Button, onClick = onBack).padding(12.dp), tint = Ink.Text)
            Text("Developer", style = plex(700, 22, color = Ink.Text))
        }
    }) {
        GroupLabel("Map")
        MapDetails(model)
        GroupLabel("Positioning", Modifier.padding(top = 6.dp))
        PositioningDetails(model)
        GroupLabel("Field test", Modifier.padding(top = 6.dp))
        FieldTest(model)
        GroupLabel("Localization", Modifier.padding(top = 6.dp))
        Localization(model)
        GroupLabel("Log", Modifier.padding(top = 6.dp))
        LogCard(model)
    }
}

@Composable
private fun Detail(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.weight(1f), style = plex(400, 15, color = Ink.Muted))
        Text(value, style = plex(500, 15, mono = true, color = Ink.Text))
    }
}

@Composable
private fun Note(text: String) = Text(text, style = plex(400, 13, 1.4f, color = Ink.Muted))

@Composable
private fun MapDetails(model: AppModel) {
    val m by model.maps.collectAsStateWithLifecycle()
    StaffCard {
        val selected = m.available.firstOrNull { it.slug == m.selectedSlug }
        Detail("Map", m.map?.name ?: selected?.name ?: "none")
        m.map?.let { map ->
            Detail("Places", "${map.pois.count { it.isNamed }} named, ${map.edges.size} paths")
            val ids = map.alignment?.mapIds.orEmpty()
            if (ids.isNotEmpty()) {
                Detail("Immersal map", ids.joinToString())
                Detail("On this phone", when {
                    m.downloading -> "Downloading…"
                    m.cached.size == ids.size -> "Yes (offline)"
                    else -> "No (cloud only)"
                })
                if (m.cached.size < ids.size && !m.downloading) {
                    StaffButton("Download for offline use", StaffButtonStyle.PLAIN, Modifier.fillMaxWidth(), icon = AiseeIcons.Download) { model.downloadMaps() }
                }
            }
        }
        if (m.offline) Note("Offline: using the copy saved on this phone.")
        m.status?.let { Note(it) }
        StaffButton("Refresh map list", StaffButtonStyle.PLAIN, Modifier.fillMaxWidth()) { model.refreshMaps() }
    }
}

@Composable
private fun PositioningDetails(model: AppModel) {
    val p by model.position.collectAsStateWithLifecycle()
    val m by model.maps.collectAsStateWithLifecycle()
    val spoken by model.spoken.collectAsStateWithLifecycle()
    StaffCard {
        val source by model.source.collectAsStateWithLifecycle()
        Detail("Source", source.label)
        Detail("Running", if (p.running) "yes" else "no")
        p.tracking?.let { Detail("Tracking", it) }
        p.localizer?.let { Detail("Localizer", it) }
        if (p.running || p.attempts > 0) {
            Detail("Fixes", "${p.fixes} of ${p.attempts}" + if (p.rejected > 0) " · ${p.rejected} rejected" else "")
            p.lastLatencyMs?.let { Detail("Last try", "$it ms") }
            p.frameSize?.let { Detail("Frame sent", "${it.first}×${it.second}") }
            p.lastError?.let { Detail("Last result", it) }
        }
        p.lastFix?.let { fix ->
            Detail("Position", "x %.1f  z %.1f m".format(fix.position.x, fix.position.z))
            Detail("Heading", "${Math.toDegrees(fix.heading.toDouble()).roundToInt()}°")
            Detail("Fix age", "${(System.currentTimeMillis() - fix.atMillis) / 1000}s")
            m.map?.let { map -> LocationDescriber(map).describe(fix.position, fix.heading)?.let { Text(it, style = plex(500, 15, 1.4f, color = Ink.Text)) } }
        }
        spoken?.let { Note("Last spoken: $it") }
        m.map?.let { MapCanvas(it, p.lastFix) }
    }
}

@Composable
private fun FieldTest(model: AppModel) {
    val m by model.maps.collectAsStateWithLifecycle()
    val checks by model.checks.collectAsStateWithLifecycle()
    val busy by model.fieldBusy.collectAsStateWithLifecycle()
    val p by model.position.collectAsStateWithLifecycle()
    StaffCard {
        Note("Stand on a marked point and tap I'm here: for 10 seconds the app records the positions and how far they are from the point. Results go to the team's server.")
        val points = remember(m.map) { model.markedPoints() }
        when {
            m.map == null -> Note("Load a map first.")
            points.isEmpty() -> Note("No points marked yet: mark them with the iPhone app's Field Test first.")
            !p.running -> Note("Start positioning to check.")
        }
        points.forEach { poi ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(poi.name, style = plex(500, 16, color = Ink.Text))
                    checks[poi.id]?.let { Note(it) }
                }
                StaffButton("I'm here", StaffButtonStyle.PRIMARY, enabled = busy == null && p.running) { model.check(poi) }
            }
        }
        busy?.let { Text(it, style = plex(500, 15, color = Ink.Text)) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StaffButton("Reload map", StaffButtonStyle.PLAIN, Modifier.weight(1f), enabled = busy == null) { model.reloadMap() }
            StaffButton("Send log", StaffButtonStyle.PLAIN, Modifier.weight(1f), enabled = busy == null) { model.sendLog() }
        }
        Note("Reload map picks up points just marked on the iPhone; start positioning again afterwards.")
    }
}

@Composable
private fun Localization(model: AppModel) {
    val focal by model.focalPx.collectAsStateWithLifecycle()
    val token by model.tokenOverride.collectAsStateWithLifecycle()
    val mode by model.localizerMode.collectAsStateWithLifecycle()
    StaffCard {
        Segmented(AppModel.LocalizerMode.entries.map { it.label }, AppModel.LocalizerMode.entries.indexOf(mode), AppModel.LocalizerMode.entries.map { true }) {
            model.setLocalizerMode(AppModel.LocalizerMode.entries[it])
        }
        Note("Auto uses the Immersal server when the phone has internet and the phone otherwise. On phone needs the map downloaded; Immersal server needs internet.")
        Detail("Lens focal length", "${focal.roundToInt()} px @1280")
        Slider(value = focal, onValueChange = { model.setFocal((it / 25).roundToInt() * 25f) }, valueRange = 600f..1400f,
            colors = SliderDefaults.colors(thumbColor = Ink.Primary, activeTrackColor = Ink.Primary))
        Note("1100 px was measured on iOS for these glasses. Takes effect on the next positioning start.")
        OutlinedTextField(
            value = token, onValueChange = model::setTokenOverride,
            label = { Text("Immersal token") },
            placeholder = { Text(if (model.hasBuiltInToken) "Built in" else "Required") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
        )
        Detail("On-device localizer", if (model.nativeAvailable) "available" else "missing")
    }
}

@Composable
private fun LogCard(model: AppModel) {
    val lines by model.log.collectAsStateWithLifecycle()
    var open by remember { mutableStateOf(false) }
    StaffCard {
        StaffButton(if (open) "Hide (${lines.size})" else "Show (${lines.size})", StaffButtonStyle.PLAIN, Modifier.fillMaxWidth()) { open = !open }
        if (open) lines.takeLast(60).reversed().forEach { Text(it, style = plex(400, 11, 1.3f, mono = true, color = Ink.Body)) }
    }
}
