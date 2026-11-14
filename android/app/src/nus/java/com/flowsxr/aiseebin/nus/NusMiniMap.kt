package com.flowsxr.aiseebin.nus

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.route.LevelChangeKind
import com.flowsxr.aiseebin.route.RouteCue
import com.flowsxr.aiseebin.route.RouteGraph
import kotlin.math.cos
import kotlin.math.sin

/**
 * A small map over the camera view: the paths on the visitor's own floor, the
 * route, where it ends or leaves the floor, and the visitor in the middle
 * facing up the screen. Tap to see further. Port of iOS `NUSMiniMap`.
 *
 * One floor at a time: the upstairs corridors sit right above the ones below,
 * so drawing both would be unreadable.
 */
@Composable
fun NusMiniMap(graph: RouteGraph, pose: MapPose, cue: RouteCue?, destinationId: String?) {
    var wide by remember { mutableStateOf(false) }
    val side by animateDpAsState(if (wide) 300.dp else 150.dp, label = "map size")
    val measurer = rememberTextMeasurer()
    val steps = rememberVectorPainter(NusIcons.Steps)
    val lift = rememberVectorPainter(NusIcons.Lift)
    val flag = rememberVectorPainter(NusIcons.Flag)
    val levels = graph.levels
    val level = cue?.userLevel ?: levels.level(pose.height)
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier.shadow(8.dp, shape).clip(shape).background(Nus.Canvas.copy(alpha = 0.94f)).border(2.dp, Color.White, shape)
            .width(side)
            .clickable(role = Role.Button, onClickLabel = if (wide) "Shrink the map" else "Enlarge the map") { wide = !wide },
    ) {
        Canvas(Modifier.size(side)) { drawMap(graph, pose, cue, destinationId, level, wide, measurer, steps, lift, flag) }
        if (levels.isMultiLevel) {
            Text("Level $level", color = Nus.InkSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().background(Color.White).padding(vertical = 3.dp))
        }
    }
}

private fun DrawScope.drawMap(
    graph: RouteGraph, pose: MapPose, cue: RouteCue?, destinationId: String?, level: Int, wide: Boolean,
    measurer: TextMeasurer, steps: VectorPainter, lift: VectorPainter, flag: VectorPainter,
) {
    val map = graph.map
    val levels = graph.levels
    val dp = density
    // The route on this floor ends at the place, or where it leaves the floor.
    var routeEnd: Int? = null
    val run = cue?.let { it.run ?: levels.stairRun(it.path, it.target) }
    if (cue != null && cue.path.isNotEmpty()) {
        val stage = cue.stage
        routeEnd = when {
            stage is RouteCue.Stage.OnStairs -> stage.run.end
            run != null -> run.start
            else -> cue.path.size - 1
        }
    }
    // Metres from the visitor to the top edge of the map. The small map zooms
    // in as the end of the route gets close, so the two never overlap.
    var range = if (wide) 34f else 15f
    if (!wide && cue != null && routeEnd != null) {
        graph.node(cue.path[routeEnd])?.let { range = (it.position.distanceTo(pose.position) * 1.5f).coerceIn(6f, 15f) }
    }
    val centre = Offset(size.width / 2, size.height * 0.62f)
    val scale = (centre.y - 10 * dp) / range
    // Heading h faces (sin h, −cos h) on (x, z); the visitor's right is (cos h, sin h).
    val forward = Vec2(sin(pose.heading), -cos(pose.heading))
    val right = Vec2(cos(pose.heading), sin(pose.heading))
    fun pt(p: Vec2): Offset {
        val d = p - pose.position
        return Offset(centre.x + (d.x * right.x + d.z * right.z) * scale, centre.y - (d.x * forward.x + d.z * forward.z) * scale)
    }
    /** Pulls a point that is off the map back onto its edge, so a far place still shows which way it is. */
    fun clamped(p: Offset, inset: Float): Offset {
        val box = Rect(inset, inset, size.width - inset, size.height - inset)
        if (box.contains(p)) return p
        val dx = p.x - centre.x; val dy = p.y - centre.y
        var t = 1f
        if (dx > 0) t = minOf(t, (box.right - centre.x) / dx)
        if (dx < 0) t = minOf(t, (box.left - centre.x) / dx)
        if (dy > 0) t = minOf(t, (box.bottom - centre.y) / dy)
        if (dy < 0) t = minOf(t, (box.top - centre.y) / dy)
        return Offset(centre.x + dx * t, centre.y + dy * t)
    }
    fun onFloor(id: String) = levels.levelOf(id) == level

    // Paths on this floor.
    val paths = Path()
    for (edge in map.edges) {
        if (!onFloor(edge.from) || !onFloor(edge.to)) continue
        val a = graph.node(edge.from) ?: continue
        val b = graph.node(edge.to) ?: continue
        val pa = pt(a.position); val pb = pt(b.position)
        paths.moveTo(pa.x, pa.y); paths.lineTo(pb.x, pb.y)
    }
    drawPath(paths, Nus.InkSecondary.copy(alpha = 0.28f), style = Stroke(5 * dp, cap = StrokeCap.Round))

    // The route: from the visitor to the place, or to where it leaves this floor.
    var end: Triple<Offset, String, Boolean>? = null
    if (cue != null && cue.path.isNotEmpty()) {
        val line = Path().apply { moveTo(centre.x, centre.y) }
        val last = routeEnd ?: (cue.path.size - 1)
        for (i in cue.target..last) {
            val poi = graph.node(cue.path[i]) ?: continue
            val p = pt(poi.position)
            line.lineTo(p.x, p.y)
            end = Triple(p, poi.id, last < cue.path.size - 1)
        }
        drawPath(line, Color.White, style = Stroke(8 * dp, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(line, Nus.Orange, style = Stroke(5 * dp, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }

    // Places on this floor, named when there is room.
    val label = TextStyle(color = Nus.Ink, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    for (poi in map.pois) {
        if (!poi.isDestination || !onFloor(poi.id) || poi.id == destinationId) continue
        val p = pt(poi.position)
        if (!Rect(6 * dp, 6 * dp, size.width - 6 * dp, size.height - 6 * dp).contains(p)) continue
        drawCircle(Color.White, 5.5f * dp, p)
        drawCircle(Nus.Blue, 4 * dp, p)
        if (wide) drawLabel(measurer, poi.name, label, Offset(p.x, p.y + 11 * dp), above = false)
    }

    // The visitor: a view wedge and a dot.
    drawArc(Nus.Blue.copy(alpha = 0.22f), startAngle = -125f, sweepAngle = 70f, useCenter = true,
        topLeft = Offset(centre.x - 26 * dp, centre.y - 26 * dp), size = Size(52 * dp, 52 * dp))
    drawCircle(Color.White, 7 * dp, centre)
    drawCircle(Nus.Blue, 4.5f * dp, centre)

    // Where the route ends on this floor: the place, or the stairs.
    end?.let { (point, id, leavesFloor) ->
        val p = clamped(point, 16 * dp)
        drawCircle(Color.White, 15 * dp, p)
        drawCircle(if (leavesFloor) Nus.Blue else Nus.Orange, 13 * dp, p)
        val painter = if (!leavesFloor) flag else if (run?.kind == LevelChangeKind.LIFT) lift else steps
        val icon = 15 * dp
        translate(p.x - icon / 2, p.y - icon / 2) {
            with(painter) { draw(Size(icon, icon), colorFilter = ColorFilter.tint(Color.White)) }
        }
        val bold = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold)
        // Above the badge, away from the visitor's dot; below it at the top edge.
        val above = p.y > 34 * dp
        val at = Offset(p.x.coerceIn(30 * dp, size.width - 30 * dp), if (above) p.y - 15 * dp else p.y + 15 * dp)
        if (leavesFloor && run != null) {
            drawLabel(measurer, "${if (run.up) "Up" else "Down"} to L${run.toLevel}", bold.copy(color = Nus.Blue), at, above)
        } else if (!leavesFloor) {
            graph.node(id)?.name?.let { drawLabel(measurer, it, bold.copy(color = Nus.Ink), at, above) }
        }
    }
}

/** One line of text centred on [at]: its bottom there when [above], else its top. Kept inside the map. */
private fun DrawScope.drawLabel(measurer: TextMeasurer, text: String, style: TextStyle, at: Offset, above: Boolean) {
    val layout = measurer.measure(text, style, maxLines = 1)
    val x = (at.x - layout.size.width / 2f).coerceIn(2f, maxOf(2f, size.width - layout.size.width - 2f))
    val y = if (above) at.y - layout.size.height else at.y
    // A white plate so the name reads over paths and the route.
    val pad = 3 * density
    drawRoundRect(Color.White.copy(alpha = 0.88f), topLeft = Offset(x - pad, y), size = Size(layout.size.width + 2 * pad, layout.size.height.toFloat()),
        cornerRadius = CornerRadius(4 * density))
    drawText(layout, topLeft = Offset(x, y))
}
