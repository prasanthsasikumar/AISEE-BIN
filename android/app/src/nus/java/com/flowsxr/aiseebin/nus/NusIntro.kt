package com.flowsxr.aiseebin.nus

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flowsxr.aiseebin.R
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.route.RouteGraph
import org.json.JSONObject
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** Words and layout the welcome map shares with iOS (`NUSTourOverview`). */
object TourOverview {
    fun summary(stops: Int, floors: Int): String {
        val intro = "This is a self-guided tour of the School of Computing. Hold up your phone and follow the orange arrows on the floor"
        if (stops <= 0) return "$intro."
        val places = "$stops place${if (stops == 1) "" else "s"}" + if (floors > 1) " across $floors floors" else ""
        return "$intro to $places. The whole tour takes about ten minutes."
    }

    /** Moves badges that would overlap apart, a little at a time, so each number can be read. */
    fun spread(points: List<Vec2>, minDistance: Float): List<Vec2> {
        val x = points.map { it.x }.toFloatArray()
        val y = points.map { it.z }.toFloatArray()
        repeat(12) {
            for (i in x.indices) for (j in i + 1 until x.size) {
                var dx = x[j] - x[i]
                var dy = y[j] - y[i]
                var d = hypot(dx, dy)
                if (d >= minDistance) continue
                if (d < 0.01f) { dx = 1f; dy = 0f; d = 1f }
                val push = (minDistance - d) / 2
                x[i] -= dx / d * push; y[i] -= dy / d * push
                x[j] += dx / d * push; y[j] += dy / d * push
            }
        }
        return x.indices.map { Vec2(x[it], y[it]) }
    }
}

/** Level 1 is blue, every floor above it orange. */
private fun levelColour(level: Int): Color = if (level <= 1) Nus.Blue else Nus.Orange

/** Welcome, shown on the first launch: what this is, and the tour on a map. Port of iOS `NUSIntroView`. */
@Composable
fun NusIntroScreen(model: NusModel, maps: NusMaps, onDone: () -> Unit) {
    val graph = maps.graph
    val places = if (graph != null) model.places else emptyList()
    val floors = graph?.levels?.levelHeights?.size ?: 1
    LaunchedEffect(Unit) { model.log("intro.shown", JSONObject()) }
    Surface(color = Nus.Canvas, modifier = Modifier.fillMaxSize()) {
        Column(Modifier.systemBarsPadding()) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Image(painterResource(R.drawable.nus_logo), contentDescription = "NUS Computing", contentScale = ContentScale.Fit,
                    modifier = Modifier.height(40.dp))
                Text("Welcome to NUS Computing", color = Nus.Ink, fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() })
                Text(TourOverview.summary(places.size, floors), color = Nus.InkSecondary, fontSize = 17.sp, lineHeight = 23.sp)

                if (graph == null || places.isEmpty()) {
                    Box(Modifier.fillMaxWidth().heightIn(min = 160.dp).background(Nus.Card, RoundedCornerShape(22.dp)),
                        contentAlignment = Alignment.Center) {
                        Text("Getting the building map…", color = Nus.InkSecondary, fontSize = 15.sp)
                    }
                } else {
                    Column(Modifier.fillMaxWidth().background(Nus.Card, RoundedCornerShape(22.dp)).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NusTourMap(graph, places)
                        // Two columns, filled row by row, as on iOS.
                        places.withIndex().chunked(2).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                row.forEach { (index, poi) ->
                                    val level = graph.levels.levelOf(poi.id)
                                    Row(
                                        Modifier.weight(1f).clearAndSetSemantics {
                                            contentDescription = "${index + 1}, ${poi.name}" + if (graph.levels.isMultiLevel) ", Level $level" else ""
                                        },
                                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Box(Modifier.size(22.dp).background(levelColour(level), CircleShape), contentAlignment = Alignment.Center) {
                                            Text("${index + 1}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        }
                                        Text(poi.name, color = Nus.Ink, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                                if (row.size == 1) Box(Modifier.weight(1f))
                            }
                        }
                        if (graph.levels.isMultiLevel) {
                            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.clearAndSetSemantics { }) {
                                for (level in 1..floors) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Box(Modifier.size(10.dp).background(levelColour(level), CircleShape))
                                        Text("Level $level", color = Nus.InkSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }
                        }
                    }
                    Text("The tour starts from the stop nearest to you, and you can skip any stop.", color = Nus.InkSecondary, fontSize = 13.sp)
                }
            }
            NusButton("Got it", Nus.Orange, onClick = onDone, modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp))
        }
    }
}

/** The whole tour from above: every path, and the stops numbered in tour order. Port of iOS `NUSTourMap`. */
@Composable
private fun NusTourMap(graph: RouteGraph, places: List<NavigationPoi>) {
    val measurer = rememberTextMeasurer()
    val map = graph.map
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Canvas(
            Modifier.widthIn(max = 300.dp).fillMaxWidth().aspectRatio(1f).background(Nus.Canvas, RoundedCornerShape(16.dp))
                .semantics { contentDescription = "Map of the tour with ${places.size} numbered stops" },
        ) {
            if (map.pois.isEmpty()) return@Canvas
            val minX = map.pois.minOf { it.position.x }; val maxX = map.pois.maxOf { it.position.x }
            val minZ = map.pois.minOf { it.position.z }; val maxZ = map.pois.maxOf { it.position.z }
            val pad = 18.dp.toPx()
            val span = max(max(maxX - minX, maxZ - minZ), 1f)
            val scale = (min(size.width, size.height) - 2 * pad) / span
            val ox = (size.width - (maxX - minX) * scale) / 2
            val oy = (size.height - (maxZ - minZ) * scale) / 2
            fun pt(p: Vec2) = Offset(ox + (p.x - minX) * scale, oy + (p.z - minZ) * scale)
            val grey = Nus.InkSecondary.copy(alpha = 0.3f)
            for (edge in map.edges) {
                val a = graph.node(edge.from) ?: continue
                val b = graph.node(edge.to) ?: continue
                drawLine(grey, pt(a.position), pt(b.position), strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
            }
            val badges = TourOverview.spread(places.map { pt(it.position).let { o -> Vec2(o.x, o.y) } }, 26.dp.toPx())
            val style = TextStyle(color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            badges.forEachIndexed { index, b ->
                val centre = Offset(b.x, b.z)
                drawCircle(levelColour(graph.levels.levelOf(places[index].id)), 12.dp.toPx(), centre)
                drawCircle(Color.White, 12.dp.toPx(), centre, style = Stroke(2.dp.toPx()))
                val text = measurer.measure("${index + 1}", style)
                drawText(text, topLeft = Offset(centre.x - text.size.width / 2f, centre.y - text.size.height / 2f))
            }
        }
    }
}
