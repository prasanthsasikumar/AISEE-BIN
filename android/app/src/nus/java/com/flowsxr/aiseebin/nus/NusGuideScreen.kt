package com.flowsxr.aiseebin.nus

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.R
import com.flowsxr.aiseebin.phone.ArCameraView
import com.flowsxr.aiseebin.phone.ArSupport
import com.flowsxr.aiseebin.route.LevelChangeKind
import com.flowsxr.aiseebin.route.RouteCue
import com.flowsxr.aiseebin.route.StairRun
import com.flowsxr.aiseebin.route.TurnDirection
import kotlin.math.roundToInt

/**
 * The camera view with arrows on the floor, a small map, a header with the
 * stop, and a card with what to do next. Port of iOS `NUSGuideView`.
 */
@Composable
fun NusGuideScreen(model: NusModel, tour: TourState, maps: NusMaps, cameraGranted: Boolean,
                   requestCamera: () -> Unit, onStaff: () -> Unit) {
    val nav by model.nav.collectAsStateWithLifecycle()
    val pose by model.mapPose.collectAsStateWithLifecycle()
    val support by model.ar.support.collectAsStateWithLifecycle()
    val arError by model.ar.error.collectAsStateWithLifecycle()
    var hint by remember { mutableStateOf(RouteHint.HIDDEN) }
    val overlay = remember(model) { RouteOverlay(model.phone) { hint = it } }
    SideEffect { overlay.scene = RouteScene(tour.phase, tour.current?.id, nav, maps.graph) }

    val graph = maps.graph
    val reliable = pose != null
    // From the map pose, which changes a few times a second; the camera view works out its own each frame.
    val cue = pose?.let { p ->
        if (graph != null && nav.navigating && nav.path.isNotEmpty())
            RouteCue(nav.path, nav.leg, p.position, p.height, graph.levels) { graph.node(it)?.position }
        else null
    }
    val cameraProblem = when {
        !cameraGranted -> "The guide needs the camera to see where you are."
        support == ArSupport.UNSUPPORTED -> "This phone can't run the camera guide: it has no Google Play Services for AR."
        else -> arError
    }

    Box(Modifier.fillMaxSize().background(Color(0xFF10151F))) {
        if (cameraGranted && support != ArSupport.UNSUPPORTED) {
            ArCameraView(model.ar, model::onArFrame, Modifier.fillMaxSize(), overlay)
        }
        Column(Modifier.fillMaxSize()) {
            Header(model, tour, onStaff)
            val p = pose
            if (tour.phase == TourPhase.LEADING && p != null && graph != null) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 10.dp), contentAlignment = Alignment.TopEnd) {
                    NusMiniMap(graph, p, cue, tour.current?.id)
                }
            }
            Spacer(Modifier.weight(1f))
            val notice = tour.notice
            if (notice != null) {
                NoticeBanner(notice)
            } else if (tour.phase == TourPhase.LEADING && cue != null && (hint == RouteHint.LEFT || hint == RouteHint.RIGHT || hint == RouteHint.DOWN)) {
                LookHint(hint)
            }
            val stairsText = cue?.stairsText
            val run = cue?.run
            Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) {
                when (tour.phase) {
                    TourPhase.LEADING -> when {
                        cameraProblem != null -> CameraCard(cameraProblem, if (cameraGranted) null else requestCamera)
                        cue != null && stairsText != null && run != null -> StairsCard(model, tour, cue, stairsText, run)
                        else -> LeadingCard(model, tour, nav, reliable)
                    }
                    TourPhase.ARRIVED -> ArrivedCard(model, tour)
                    TourPhase.FINISHED -> FinishedCard(model, tour)
                    TourPhase.HOME -> Unit
                }
            }
        }
    }
}

// MARK: Header

@Composable
private fun Header(model: NusModel, tour: TourState, onStaff: () -> Unit) {
    val stop = tour.current
    val title = when {
        tour.startPending -> "Finding where you are"
        stop == null || tour.phase == TourPhase.FINISHED -> if (tour.phase == TourPhase.FINISHED) "Tour complete" else "NUS Computing Tour"
        else -> stop.name
    }
    val level = stop?.let { model.guide.levelName(it.id) }
    val subtitle = when {
        tour.startPending -> "The tour starts from the nearest stop"
        stop == null || tour.phase == TourPhase.FINISHED -> null
        tour.isTour -> listOfNotNull("Stop ${tour.index + 1} of ${tour.stops.size}", level).joinToString(" · ")
        else -> level
    }
    Row(
        Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.9f)).windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // No logo here: the lockup is too wide to sit beside the stop's name. It is on the home screen.
        Column(Modifier.weight(1f).staffTaps(onStaff)) {
            Text(title, color = Nus.Ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, color = Nus.Orange, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
        Box(
            Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button, onClickLabel = "End") { model.guide.exit() },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(40.dp).background(Nus.Canvas, CircleShape), contentAlignment = Alignment.Center) {
                Icon(NusIcons.Close, contentDescription = "End", tint = Nus.Ink, modifier = Modifier.size(22.dp))
            }
        }
    }
}

// MARK: Cards

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.padding(16.dp).fillMaxWidth().shadow(12.dp, RoundedCornerShape(22.dp))
            .background(Nus.Card, RoundedCornerShape(22.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) { content() }
}

@Composable
private fun LeadingCard(model: NusModel, tour: TourState, nav: NavState, reliable: Boolean) {
    val instruction = nav.instruction
    val problem = nav.problem
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val icon = if (!reliable) NusIcons.Camera else instructionIcon(if (nav.offRoute) null else instruction?.direction)
            Icon(icon, contentDescription = null, tint = if (reliable) Nus.Orange else Nus.Warn, modifier = Modifier.size(30.dp))
            Spacer(Modifier.width(10.dp))
            Text(
                when {
                    !reliable -> "Look around slowly so I can find where you are"
                    problem != null -> problem
                    instruction == null -> "Follow the arrows"
                    nav.offRoute -> "Head back to the arrows"
                    else -> instruction.bannerText
                },
                color = Nus.Ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 25.sp,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
        if (reliable && nav.navigating) {
            Text("${NusModel.metres(nav.remaining)} to ${tour.current?.name ?: "go"} · follow the arrows", color = Nus.InkSecondary, fontSize = 15.sp)
        } else if (!reliable) {
            Text("Point your phone at walls, doors and signs.", color = Nus.InkSecondary, fontSize = 15.sp)
        }
        SkipButton(model, tour)
    }
}

/** The arrow for a turn. */
private fun instructionIcon(direction: TurnDirection?): ImageVector = when (direction) {
    TurnDirection.SLIGHT_LEFT, TurnDirection.LEFT, TurnDirection.SHARP_LEFT -> NusIcons.TurnLeft
    TurnDirection.SLIGHT_RIGHT, TurnDirection.RIGHT, TurnDirection.SHARP_RIGHT -> NusIcons.TurnRight
    TurnDirection.U_TURN -> NusIcons.UTurn
    else -> NusIcons.ArrowUp
}

@Composable
private fun SkipButton(model: NusModel, tour: TourState) {
    if (!tour.isTour || tour.startPending) return
    Text(
        tour.next?.takeIf { !tour.isLastStop }?.let { "Skip to ${it.name}" } ?: "Skip and finish the tour",
        color = Nus.Blue, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable(role = Role.Button) { model.guide.skipStop() }
            .heightIn(min = 48.dp).padding(vertical = 13.dp, horizontal = 2.dp),
    )
}

/** Stairs or a lift are next: a card of its own, big enough to read at a glance. */
@Composable
private fun StairsCard(model: NusModel, tour: TourState, cue: RouteCue, text: String, run: StairRun) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box {
                Box(Modifier.size(68.dp).background(Nus.Blue, RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                    Icon(if (run.kind == LevelChangeKind.LIFT) NusIcons.Lift else NusIcons.Steps, contentDescription = null,
                        tint = Color.White, modifier = Modifier.size(40.dp))
                }
                Box(Modifier.align(Alignment.TopEnd).offset(x = 8.dp, y = (-8).dp).size(28.dp).background(Color.White, CircleShape),
                    contentAlignment = Alignment.Center) {
                    Icon(NusIcons.ArrowCircle, contentDescription = null, tint = Nus.Orange,
                        modifier = Modifier.size(28.dp).rotate(if (run.up) 0f else 180f))
                }
            }
            Spacer(Modifier.width(18.dp))
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(text, color = Nus.Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold, lineHeight = 27.sp,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                Text(stairsDetail(model, tour, cue), color = Nus.InkSecondary, fontSize = 15.sp)
            }
        }
        SkipButton(model, tour)
    }
}

private fun stairsDetail(model: NusModel, tour: TourState, cue: RouteCue): String {
    val place = tour.current?.name ?: "the next stop"
    val level = tour.current?.let { model.graph?.levels?.levelOf(it.id) } ?: cue.run?.toLevel ?: 1
    val onLevel = "$place is on Level $level"
    val stage = cue.stage
    return if (stage is RouteCue.Stage.StairsAhead && stage.metres > 2) "${stage.metres.roundToInt()} m ahead · $onLevel" else onLevel
}

/** The camera cannot run: say why, and offer the way to fix it when there is one. */
@Composable
private fun CameraCard(problem: String, allow: (() -> Unit)?) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(NusIcons.Camera, contentDescription = null, tint = Nus.Warn, modifier = Modifier.size(30.dp))
            Spacer(Modifier.width(10.dp))
            Text(problem, color = Nus.Ink, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, lineHeight = 23.sp)
        }
        if (allow != null) NusButton("Allow the camera", Nus.Blue, onClick = allow)
    }
}

@Composable
private fun NoticeBanner(text: String) {
    Row(
        Modifier.padding(horizontal = 16.dp).shadow(8.dp, CircleShape).background(Nus.Blue, CircleShape)
            .padding(horizontal = 18.dp, vertical = 12.dp).semantics { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(NusIcons.Skip, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun LookHint(hint: RouteHint) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        contentAlignment = when (hint) { RouteHint.LEFT -> Alignment.CenterStart; RouteHint.RIGHT -> Alignment.CenterEnd; else -> Alignment.Center }) {
        Row(Modifier.background(Nus.Blue.copy(alpha = 0.9f), CircleShape).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (hint == RouteHint.LEFT) Icon(NusIcons.ArrowUp, null, tint = Color.White, modifier = Modifier.size(20.dp).rotate(-90f))
            if (hint == RouteHint.DOWN) Icon(NusIcons.ArrowUp, null, tint = Color.White, modifier = Modifier.size(20.dp).rotate(180f))
            Text(if (hint == RouteHint.DOWN) "Tilt your phone down to see the arrows" else "Turn ${if (hint == RouteHint.LEFT) "left" else "right"} to see the arrows",
                color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            if (hint == RouteHint.RIGHT) Icon(NusIcons.ArrowUp, null, tint = Color.White, modifier = Modifier.size(20.dp).rotate(90f))
        }
    }
}

@Composable
private fun ArrivedCard(model: NusModel, tour: TourState) {
    val stop = tour.current
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.socat_wave), contentDescription = null, modifier = Modifier.size(52.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }) {
                Text("You've arrived!", color = Nus.Ok, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Text(stop?.name.orEmpty(), color = Nus.Ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
        }
        (stop?.details ?: stop?.about)?.takeIf { it.isNotEmpty() }?.let {
            Text(it, color = Nus.InkSecondary, fontSize = 17.sp, lineHeight = 23.sp)
        }
        val next = tour.next
        if (tour.isTour && !tour.isLastStop && next != null) {
            NusButton("Next: ${next.name}", Nus.Orange, onClick = { model.guide.nextStop() })
        } else {
            NusButton(if (tour.isTour) "Finish the tour" else "Done", Nus.Blue,
                onClick = { if (tour.isTour) model.guide.nextStop() else model.guide.exit() })
        }
    }
}

@Composable
private fun FinishedCard(model: NusModel, tour: TourState) {
    Card {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Image(painterResource(R.drawable.socat_wave), contentDescription = null, modifier = Modifier.height(80.dp))
            Text("Tour complete!", color = Nus.Ink, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text("You've visited all ${tour.stops.size} stops. Thanks for exploring NUS Computing.", color = Nus.InkSecondary,
                fontSize = 17.sp, textAlign = TextAlign.Center)
            NusButton("Back to start", Nus.Blue, onClick = { model.guide.exit() })
        }
    }
}
