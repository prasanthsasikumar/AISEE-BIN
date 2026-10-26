package com.flowsxr.aiseebin.ui

import android.view.ViewGroup
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.AppModel
import com.flowsxr.aiseebin.glasses.Stream
import com.flowsxr.aiseebin.map.LocationDescriber
import com.realsil.sdk.audioconnect.smartwear.live.view.RTKVideoView
import kotlinx.coroutines.delay
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.flowsxr.aiseebin.phone.ArCameraView

/**
 * Navigate (design B and 02): the shared header, a state pill, the camera
 * (the phone's with ARCore, or the glasses' video), a hint, the talk tile and
 * one next-step button. Destinations and guidance come with the routing port.
 */
@Composable
fun NavigateScreen(model: AppModel, chip: ChipState, cameraAllowed: Boolean, onLogo: () -> Unit, onChip: () -> Unit,
                   onSettings: () -> Unit, onConnect: () -> Unit, onAllowCamera: () -> Unit) {
    val g by model.glasses.state.collectAsStateWithLifecycle()
    val m by model.maps.collectAsStateWithLifecycle()
    val p by model.position.collectAsStateWithLifecycle()
    val source by model.source.collectAsStateWithLifecycle()
    val arError by model.ar.error.collectAsStateWithLifecycle()
    val phone = source == AppModel.PositionSource.PHONE
    val starting by model.starting.collectAsStateWithLifecycle()
    val staff by model.staff.collectAsStateWithLifecycle()
    // Ticks so "Tracking ready" turns back into "Relocalizing…" once the fix goes stale.
    val now by produceState(System.currentTimeMillis()) { while (true) { delay(1000); value = System.currentTimeMillis() } }

    val map = m.map
    val fix = p.lastFix
    val status = navigateStatus(NavigateInputs(
        phone = phone, cameraAllowed = cameraAllowed, arError = arError, tracking = p.tracking,
        link = g.link, stream = g.stream,
        mapName = map?.name ?: m.available.firstOrNull { it.slug == m.selectedSlug }?.name,
        mapLoading = m.loading, hasAlignment = !map?.alignment?.mapIds.isNullOrEmpty(),
        starting = starting, running = p.running,
        fixAgeSeconds = fix?.let { (now - it.atMillis) / 1000 },
        whereText = fix?.let { f -> map?.let { LocationDescriber(it).describe(f.position, f.heading) } },
    ))

    // The phone camera starts positioning by itself once it can, as iOS does; a Stop holds until the next visit.
    var userStopped by rememberSaveable { mutableStateOf(false) }
    val phoneReady = phone && cameraAllowed && arError == null && map != null && !map.alignment?.mapIds.isNullOrEmpty() && !m.loading
    LaunchedEffect(phoneReady, p.running, starting) {
        if (phoneReady && !p.running && !starting && !userStopped) model.startPositioning()
    }

    Column(Modifier.fillMaxSize().background(Ink.Night)) {
        VisitorHeader(staff, chip, onLogo, onChip, onSettings)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (phone && cameraAllowed) ArCameraView(model.ar, model::onArFrame, Modifier.fillMaxSize())
            else DotField(status.tone)
            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                StatePill(status.pill, status.tone, status.pulse)
                if (m.downloading) DownloadCard(m.available.firstOrNull { it.slug == m.selectedSlug }?.version)
                if (phone) {
                    Box(Modifier.weight(1f))
                    // Staff see the fix on the map over the camera; visitors get the clean view.
                    if (staff && map != null) MapCanvas(map, fix,
                        Modifier.clip(RoundedCornerShape(20.dp)).background(Color(0xD917151F)), height = 170.dp)
                } else {
                    val live = g.stream == Stream.STARTING || g.stream == Stream.PLAYING
                    if (live) GlassesVideo(g.stream, g.fps)
                    if (map != null) MapCanvas(map, fix, Modifier.weight(1f).clip(RoundedCornerShape(20.dp)), height = null)
                    else Box(Modifier.weight(1f))
                }
                HintBanner(status.hint, status.tone)
            }
        }
        BottomBar(status, onWhereAmI = { model.whereAmI() }, onStep = {
            when (status.step) {
                NextStep.CHOOSE_MAP -> onChip()
                NextStep.CONNECT -> onConnect()
                NextStep.START_CAMERA -> model.startCamera()
                NextStep.ALLOW_CAMERA -> onAllowCamera()
                NextStep.USE_GLASSES -> model.setSource(AppModel.PositionSource.GLASSES)
                NextStep.START_POSITIONING -> { userStopped = false; model.startPositioning() }
                NextStep.STOP_POSITIONING -> { userStopped = true; model.stopPositioning() }
                NextStep.NONE -> Unit
            }
        })
    }
}

/** The design's dotted backdrop: lavender when ready, amber while waiting. */
@Composable
private fun DotField(tone: Tone) {
    val dot = if (tone == Tone.WAIT) Color(0x66FFC24B) else Color(0x8CB9A6FF)
    Canvas(Modifier.fillMaxSize()) {
        val stepX = 34.dp.toPx(); val stepY = 29.dp.toPx(); val r = 1.2.dp.toPx()
        var y = stepY / 2
        while (y < size.height) {
            var x = stepX / 2
            while (x < size.width) { drawCircle(dot.copy(alpha = dot.alpha * 0.22f / 0.4f), r, Offset(x, y)); x += stepX }
            y += stepY
        }
        drawRect(Brush.radialGradient(listOf(Color(0x299B87E8), Color.Transparent), Offset(size.width / 2, size.height * 0.3f), size.width * 0.9f))
    }
}

@Composable
private fun DownloadCard(version: Int?) {
    Column(
        Modifier.fillMaxWidth().panel(Color(0xEB17151F), RoundedCornerShape(22.dp), Color(0x4DB9A6FF), 1.dp).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(AiseeIcons.Download, null, Modifier.size(22.dp), tint = Ink.Accent)
            Text("Downloading map${version?.let { " v$it" } ?: ""}", style = plex(600, 18, color = Ink.Light))
        }
        LinearProgressIndicator(Modifier.fillMaxWidth().heightIn(min = 12.dp).clip(RoundedCornerShape(8.dp)), color = Ink.Accent, trackColor = Ink.Track)
        Text("Saving it on this phone so the glasses work without internet.", style = plex(400, 15, 1.4f, color = Ink.MutedDark))
    }
}

/**
 * The SDK's video. A SurfaceView composited above the window (see the note in
 * the old screen: behind it, Compose's window went transparent), so nothing is
 * drawn over it.
 */
@Composable
private fun GlassesVideo(stream: Stream, fps: Int) {
    Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(20.dp)).background(Color.Black)
        .semantics { contentDescription = if (stream == Stream.PLAYING) "Glasses camera, live" else "Glasses camera, starting" }) {
        AndroidView(
            factory = { ctx ->
                RTKVideoView(ctx).apply {
                    setZOrderMediaOverlay(true)
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
    if (stream == Stream.PLAYING) Text("Glasses camera · $fps fps", style = plex(500, 12, mono = true, color = Ink.Sub))
}

@Composable
private fun BottomBar(status: NavigateStatus, onWhereAmI: () -> Unit, onStep: () -> Unit) {
    Column(
        Modifier.padding(start = 12.dp, end = 12.dp, bottom = 12.dp).fillMaxWidth()
            .panel(Ink.Panel, RoundedCornerShape(36.dp), Color(0x1AF7F5FD), 1.dp).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        TalkTile(onWhereAmI)
        BigButton(
            status.action,
            when (status.step) {
                NextStep.CONNECT -> AiseeIcons.Glasses
                NextStep.START_CAMERA, NextStep.ALLOW_CAMERA -> AiseeIcons.Camera
                NextStep.USE_GLASSES -> AiseeIcons.Glasses
                NextStep.CHOOSE_MAP -> AiseeIcons.UpDown
                NextStep.START_POSITIONING, NextStep.STOP_POSITIONING -> AiseeIcons.Walk
                NextStep.NONE -> AiseeIcons.Spinner
            },
            enabled = status.enabled,
            filled = status.step != NextStep.STOP_POSITIONING,
            onClick = onStep,
        )
    }
}

/** The 180 dp talk control. Until voice input is ported it answers "where am I". */
@Composable
private fun ColumnScope.TalkTile(onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 180.dp)
            .panel(Ink.Talk, RoundedCornerShape(28.dp), Ink.Lavender)
            .clickable(role = Role.Button, onClickLabel = "hear where you are", onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 26.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Box(Modifier.size(82.dp).background(Ink.Light, CircleShape), contentAlignment = Alignment.Center) {
            Icon(AiseeIcons.Pin, null, Modifier.size(42.dp), tint = Ink.Talk)
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Where am I?", style = plex(700, 32, color = Color.White))
            Text("Tap here, or press the button on the glasses.", style = plex(400, 16, 1.45f, color = Ink.OnPrimarySoft))
        }
    }
}
