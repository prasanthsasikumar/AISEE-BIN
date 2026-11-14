package com.flowsxr.aiseebin.nus

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.BuildConfig
import com.flowsxr.aiseebin.R
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.positioning.PositioningState

private val NusColors = lightColorScheme(
    primary = Nus.Blue, onPrimary = Color.White, secondary = Nus.Orange, onSecondary = Color.White,
    background = Nus.Canvas, onBackground = Nus.Ink, surface = Nus.Card, onSurface = Nus.Ink,
    surfaceContainerLow = Nus.Card, onSurfaceVariant = Nus.InkSecondary,
)

/** The whole app: the camera guide, with the home screen over it until a tour or a place is chosen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NusRoot(
    model: NusModel, cameraGranted: Boolean, requestCamera: () -> Unit,
    showPlaces: Boolean, onShowPlaces: (Boolean) -> Unit,
    showStaff: Boolean, onShowStaff: (Boolean) -> Unit,
    showIntro: Boolean = false, onShowIntro: (Boolean) -> Unit = {},
) {
    val tour by model.guide.state.collectAsStateWithLifecycle()
    val maps by model.maps.collectAsStateWithLifecycle()
    val introSeen by model.introSeen.collectAsStateWithLifecycle()
    MaterialTheme(colorScheme = NusColors) {
        Box(Modifier.fillMaxSize().background(Nus.Canvas)) {
            // The camera runs under the home screen too, so the phone is usually
            // found by the time the visitor presses Start (as on iOS).
            NusGuideScreen(model, tour, maps, cameraGranted, requestCamera, onStaff = { onShowStaff(true) })
            AnimatedVisibility(tour.phase == TourPhase.HOME, enter = fadeIn(), exit = fadeOut()) {
                NusHomeScreen(model, maps, onChoose = { onShowPlaces(true) }, onStaff = { onShowStaff(true) },
                    onAbout = { onShowIntro(true) })
            }
            // Welcome: once on the first launch, and again from "About this tour".
            AnimatedVisibility(tour.phase == TourPhase.HOME && (!introSeen || showIntro), enter = fadeIn(), exit = fadeOut()) {
                NusIntroScreen(model, maps) {
                    model.finishIntro()
                    onShowIntro(false)
                }
            }
            if (showPlaces) {
                ModalBottomSheet(onDismissRequest = { onShowPlaces(false) }, containerColor = Nus.Card) {
                    NusPlacesList(model) { poi ->
                        onShowPlaces(false)
                        model.guide.goTo(poi)
                    }
                }
            }
            if (showStaff) NusStaffScreen(model, maps) { onShowStaff(false) }
        }
        BackHandler(enabled = tour.phase != TourPhase.HOME && !showStaff) { model.guide.exit() }
    }
}

/** The NUS Computing lockup. Five quick taps open the staff screen. */
@Composable
fun NusLogoMark(height: Dp, onStaff: () -> Unit) {
    Image(
        painterResource(R.drawable.nus_logo), contentDescription = "NUS Computing", contentScale = ContentScale.Fit,
        modifier = Modifier.height(height).staffTaps(onStaff),
    )
}

/** Five quick taps open the staff screen. */
@Composable
fun Modifier.staffTaps(onStaff: () -> Unit): Modifier {
    val taps = remember { mutableStateListOf<Long>() }
    return clickable(remember { MutableInteractionSource() }, indication = null) {
        val now = System.currentTimeMillis()
        taps.removeAll { now - it >= 3000 }
        taps += now
        if (taps.size >= 5) { taps.clear(); onStaff() }
    }
}

// MARK: - Home

@Composable
private fun NusHomeScreen(model: NusModel, maps: NusMaps, onChoose: () -> Unit, onStaff: () -> Unit, onAbout: () -> Unit) {
    val voiceOn by model.voiceOn.collectAsStateWithLifecycle()
    val hasMap = maps.map != null
    val places = model.places
    Surface(color = Nus.Canvas, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.systemBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                NusLogoMark(40.dp, onStaff)
                Spacer(Modifier.weight(1f))
                Box(
                    Modifier.size(48.dp).clip(CircleShape)
                        .clickable(role = Role.Switch) { model.setVoice(!voiceOn) }
                        .semantics { contentDescription = if (voiceOn) "Voice on" else "Voice off" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(if (voiceOn) NusIcons.VolumeUp else NusIcons.VolumeOff, contentDescription = null, tint = Nus.Blue)
                }
            }

            Spacer(Modifier.weight(1f).heightIn(min = 12.dp))

            Image(painterResource(R.drawable.socat), contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.padding(horizontal = 40.dp).heightIn(max = 190.dp))

            Column(Modifier.padding(horizontal = 28.dp).padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Hi! I'm ${Nus.MASCOT}.", color = Nus.Ink, fontSize = 32.sp, fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
                Text("Let me show you around NUS Computing. Hold up your phone and follow the arrows on the floor.",
                    color = Nus.InkSecondary, fontSize = 17.sp, lineHeight = 23.sp, textAlign = TextAlign.Center)
            }

            Spacer(Modifier.weight(1f).heightIn(min = 16.dp))

            Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                NusButton(if (hasMap) "Start the tour (${places.size} stops)" else "Start the tour", Nus.Orange,
                    onClick = { model.guide.startTour() }, icon = NusIcons.Walk, enabled = hasMap && places.isNotEmpty())
                NusButton("Choose a place", Nus.Blue, onClick = onChoose, icon = NusIcons.List, enabled = hasMap && places.isNotEmpty())
                Box(Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).clickable(role = Role.Button, onClick = onAbout)
                    .padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                    Text("About this tour", color = Nus.Blue, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
                Text(homeStatus(maps), color = Nus.InkSecondary, fontSize = 13.sp, textAlign = TextAlign.Center,
                    modifier = Modifier.heightIn(min = 20.dp))
            }
        }
    }
}

/** The line under the buttons: what the map is doing, or which map this is. */
internal fun homeStatus(maps: NusMaps): String {
    val hasMap = maps.map != null
    return when (val sync = maps.sync) {
        MapSync.Checking -> if (hasMap) maps.map?.name.orEmpty() else "Getting the building map…"
        is MapSync.Failed -> if (hasMap) maps.map?.name.orEmpty() else "Couldn't get the map: ${sync.reason}"
        MapSync.NonePublished -> if (hasMap) maps.map?.name.orEmpty() else "No building map has been published yet."
        else -> if (hasMap) maps.map?.name.orEmpty() else "No map yet. Connect to the internet to get the building map."
    }
}

// MARK: - Places

@Composable
private fun NusPlacesList(model: NusModel, onPick: (NavigationPoi) -> Unit) {
    val places = model.places
    Column(Modifier.fillMaxWidth()) {
        Text("Where to?", color = Nus.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).semantics { heading() })
        LazyColumn {
            items(places, key = { it.id }) { poi ->
                Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { onPick(poi) }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(NusIcons.Pin, contentDescription = null, tint = Nus.Orange, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(poi.name, color = Nus.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        poi.details?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, color = Nus.InkSecondary, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    model.guide.levelName(poi.id)?.let { level ->
                        Text(level, color = Nus.Blue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.background(Nus.Blue.copy(alpha = 0.1f), CircleShape).padding(horizontal = 8.dp, vertical = 4.dp))
                    }
                }
                HorizontalDivider(color = Nus.Canvas, modifier = Modifier.padding(start = 62.dp))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Staff

/**
 * Hidden staff screen (5 quick taps on the NUS logo): which map, positioning
 * state, and the switches a demo needs.
 */
@Composable
private fun NusStaffScreen(model: NusModel, maps: NusMaps, onDone: () -> Unit) {
    val state by model.phone.state.collectAsStateWithLifecycle()
    val pose by model.mapPose.collectAsStateWithLifecycle()
    val localizer by model.localizer.collectAsStateWithLifecycle()
    val problem by model.positioningProblem.collectAsStateWithLifecycle()
    val arError by model.ar.error.collectAsStateWithLifecycle()
    val voiceOn by model.voiceOn.collectAsStateWithLifecycle()
    BackHandler(onBack = onDone)
    LaunchedEffect(Unit) { model.refreshMaps() }
    Surface(color = Nus.Canvas, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Staff", color = Nus.Ink, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
                Text("Done", color = Nus.Blue, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable(role = Role.Button, onClick = onDone).padding(horizontal = 12.dp, vertical = 12.dp))
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val graph = maps.graph
                StaffSection("Map") {
                    StaffRow("On this phone", maps.slug?.takeIf { maps.map != null }?.let { "$it${maps.version?.let { v -> " v$v" } ?: ""}" } ?: "none")
                    StaffRow("Name", maps.map?.name ?: "none")
                    StaffRow("Places", "${model.places.size} stops · ${maps.map?.pois?.size ?: 0} nodes")
                    StaffRow("Levels", graph?.levels?.levelHeights?.takeIf { it.isNotEmpty() }
                        ?.mapIndexed { i, h -> "L${i + 1} %.1f m".format(if (kotlin.math.abs(h) < 0.05f) 0f else h) }?.joinToString(" · ") ?: "no heights on this map")
                    if (maps.sync.label.isNotEmpty()) StaffNote(maps.sync.label)
                    StaffAction("Check for map updates") { model.refreshMaps() }
                }
                StaffSection("Published NUS maps") {
                    if (maps.listing) CircularProgressIndicator(Modifier.padding(12.dp).size(22.dp), strokeWidth = 2.dp, color = Nus.Blue)
                    maps.listError?.let { StaffNote(it, Color(0xFFB3261E)) }
                    for (map in maps.available) {
                        Row(Modifier.fillMaxWidth().clickable(role = Role.Button) { model.switchMap(map.slug) }.padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(map.name, color = Nus.Ink, fontSize = 16.sp)
                                Text("${map.slug} · v${map.version}", color = Nus.InkSecondary, fontSize = 12.sp)
                            }
                            when {
                                maps.switchingTo == map.slug -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Nus.Blue)
                                maps.slug == map.slug && maps.map != null ->
                                    Icon(NusIcons.Check, contentDescription = "In use", tint = Nus.Blue, modifier = Modifier.size(22.dp))
                            }
                        }
                    }
                    if (!maps.listing && maps.available.isEmpty()) {
                        StaffNote("No maps named nus-… yet. Publish one from AISEE-BIN's Author mode.")
                    }
                }
                StaffSection("Positioning") {
                    StaffRow("Status", positioningStatus(state, pose != null, problem ?: arError))
                    StaffRow("Tracking", state.tracking ?: if (state.running) "normal" else "off")
                    StaffRow("Height", pose?.let { "%.2f m (Level %d)".format(it.height, graph?.levels?.level(it.height) ?: 1) } ?: "—")
                    if (state.running) {
                        StaffNote(listOfNotNull(localizer, "${state.fixes} fixes / ${state.attempts} tries",
                            state.lastLatencyMs?.let { "last $it ms" }, state.lastError).joinToString(" · "))
                    }
                    StaffAction("Restart positioning") { model.restartPositioning() }
                }
                StaffSection("Guide") {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Voice guidance", color = Nus.Ink, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        Switch(voiceOn, onCheckedChange = model::setVoice,
                            colors = SwitchDefaults.colors(checkedTrackColor = Nus.Blue, checkedThumbColor = Color.White))
                    }
                }
                Text("NUS Computing Tour ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    color = Nus.InkSecondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            }
        }
    }
}

internal fun positioningStatus(state: PositioningState, positioned: Boolean, problem: String?): String = when {
    positioned -> "Positioned"
    !state.running -> problem ?: "Off"
    problem != null -> problem
    state.tracking != null -> "Camera not tracking"
    else -> "Finding where you are"
}

@Composable
private fun StaffSection(title: String, content: @Composable () -> Unit) {
    Text(title.uppercase(), color = Nus.InkSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp).semantics { heading() })
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Nus.Card).padding(vertical = 6.dp)) { content() }
}

@Composable
private fun StaffRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Nus.Ink, fontSize = 16.sp)
        Spacer(Modifier.width(12.dp))
        Text(value, color = Nus.InkSecondary, fontSize = 16.sp, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StaffNote(text: String, color: Color = Nus.InkSecondary) {
    Text(text, color = color, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

@Composable
private fun StaffAction(text: String, onClick: () -> Unit) {
    Text(text, color = Nus.Blue, fontSize = 16.sp,
        modifier = Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp))
}
