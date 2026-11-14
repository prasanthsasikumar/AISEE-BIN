package com.flowsxr.aiseebin.nus

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.route.RouteGraph
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Layout the home map shares with iOS (`NUSTourOverview`). */
object TourOverview {
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

/**
 * What the home screen's 3D map draws, worked out once per map: the scan's
 * point cloud, the paths and the stops. The same numbers as iOS `TourScene`.
 */
class TourScene private constructor(
    /** x, y, z triplets. */
    val points: FloatArray,
    /** ax, ay, az, bx, by, bz per path. */
    val edges: FloatArray,
    val stops: List<Stop>,
    val cx: Float, val cy: Float, val cz: Float,
    /** The larger of the map's width and depth, metres. */
    val span: Float,
    /** The heights the colours run between. */
    val lowest: Float, val highest: Float,
) {
    class Stop(val x: Float, val y: Float, val z: Float, val level: Int)

    fun band(y: Float): Int = (((y - lowest) / max(highest - lowest, 0.1f)) * BAND_COLOURS.size).toInt().coerceIn(0, BAND_COLOURS.size - 1)

    /** The camera at [progress] 0…1: it swings round and rises, easing to rest. */
    fun view(progress: Float, width: Float, height: Float): View {
        val e = 1 - (1 - progress.coerceIn(0f, 1f)).pow(3)
        return View(this, yaw = (1 - e) * -1.92f, pitch = 0.42f + e * (0.92f - 0.42f),
            scale = min(width / (span * 1.45f), height / (span * 1.02f)), width = width, height = height)
    }

    /** [yaw] is radians about the vertical (0 has the map's −z at the top); [pitch] radians down from the horizon. */
    class View(private val scene: TourScene, yaw: Float, pitch: Float, private val scale: Float, private val width: Float, private val height: Float) {
        private val cosYaw = cos(yaw); private val sinYaw = sin(yaw)
        private val cosPitch = cos(pitch); private val sinPitch = sin(pitch)
        fun x(px: Float, pz: Float): Float = width / 2 + ((px - scene.cx) * cosYaw - (pz - scene.cz) * sinYaw) * scale
        fun y(px: Float, py: Float, pz: Float): Float =
            height / 2 + (((px - scene.cx) * sinYaw + (pz - scene.cz) * cosYaw) * sinPitch - (py - scene.cy) * cosPitch) * scale
    }

    companion object {
        const val MILLIS = 3000
        const val MAX_POINTS = 36_000
        /** The card behind the cloud, and the cloud's colours from the lowest points to the highest. */
        val BACKGROUND = Color(0xFF0D1017)
        val BAND_COLOURS = listOf(Color(0xFF3F6FD8), Color(0xFF7F9BD6), Color(0xFFBFC3A0), Color(0xFFE3C85A), Color(0xFFF5C518))

        /** [cloud] is the scan's x, y, z floats, or null to draw the paths and stops alone. */
        fun of(graph: RouteGraph, cloud: FloatArray?): TourScene? {
            val map = graph.map
            if (map.pois.isEmpty()) return null
            // Floor heights: places are marked at camera height.
            fun floor(id: String) = graph.levels.floorHeight(id) ?: 0f
            val minX = map.pois.minOf { it.position.x }; val maxX = map.pois.maxOf { it.position.x }
            val minZ = map.pois.minOf { it.position.z }; val maxZ = map.pois.maxOf { it.position.z }
            val minY = map.pois.minOf { floor(it.id) }; val maxY = map.pois.maxOf { floor(it.id) }
            val cx = (minX + maxX) / 2; val cy = (minY + maxY) / 2; val cz = (minZ + maxZ) / 2
            val span = max(max(maxX - minX, maxZ - minZ), 1f)
            val edges = ArrayList<Float>(map.edges.size * 6)
            for (edge in map.edges) {
                val a = graph.node(edge.from) ?: continue
                val b = graph.node(edge.to) ?: continue
                edges += listOf(a.position.x, floor(a.id), a.position.z, b.position.x, floor(b.id), b.position.z)
            }
            val stops = map.pois.filter { it.isDestination && it.id != map.tourStart }
                .map { Stop(it.position.x, floor(it.id), it.position.z, graph.levels.levelOf(it.id)) }
            return TourScene(sample(cloud, cx, cz, span, minY - 1, maxY + 6), edges.toFloatArray(), stops, cx, cy, cz, span,
                lowest = minY - 0.5f, highest = maxY + 4)
        }

        /** An even sample of the cloud, kept to the area of the paths and to sensible heights. */
        internal fun sample(cloud: FloatArray?, cx: Float, cz: Float, span: Float, minY: Float, maxY: Float): FloatArray {
            if (cloud == null || cloud.size < 3) return FloatArray(0)
            val count = cloud.size / 3
            val stride = max(1, count / (MAX_POINTS * 5 / 4))
            val out = FloatArray(MAX_POINTS * 3)
            var n = 0
            var i = 0
            while (i < count && n < MAX_POINTS) {
                val x = cloud[i * 3]; val y = cloud[i * 3 + 1]; val z = cloud[i * 3 + 2]
                if (abs(x - cx) < span * 0.62f && abs(z - cz) < span * 0.62f && y > minY && y < maxY) {
                    out[n * 3] = x; out[n * 3 + 1] = y; out[n * 3 + 2] = z
                    n++
                }
                i += stride
            }
            return out.copyOf(n * 3)
        }
    }
}

/**
 * The building as the scan's point cloud, with the paths and the numbered
 * stops. It turns for three seconds when it appears, then rests seen from
 * above at a slight angle. Tap to play it again. Port of iOS `NUSTourCloud`.
 */
@Composable
fun NusTourCloud(scene: TourScene, modifier: Modifier = Modifier) {
    val progress = remember { Animatable(0f) }
    var replay by remember { mutableIntStateOf(0) }
    LaunchedEffect(scene, replay) {
        progress.snapTo(0f)
        progress.animateTo(1f, tween(TourScene.MILLIS, easing = LinearEasing))
    }
    val measurer = rememberTextMeasurer()
    // Points sorted into colour bands once; only their screen positions change per frame.
    val bands = remember(scene) {
        val lists = List(TourScene.BAND_COLOURS.size) { ArrayList<Int>() }
        for (i in 0 until scene.points.size / 3) lists[scene.band(scene.points[i * 3 + 1])] += i
        lists.map { it.toIntArray() }
    }
    val shape = RoundedCornerShape(22.dp)
    Canvas(
        modifier.clip(shape).background(TourScene.BACKGROUND)
            .clickable(remember { MutableInteractionSource() }, indication = null) { replay++ }
            .clearAndSetSemantics { contentDescription = "Map of the tour from above, with ${scene.stops.size} numbered stops" },
    ) {
        val t = progress.value
        val view = scene.view(t, size.width, size.height)
        val fade = min(1f, t / 0.15f)
        val p = scene.points
        bands.forEachIndexed { band, indices ->
            val dots = ArrayList<Offset>(indices.size)
            for (i in indices) dots += Offset(view.x(p[i * 3], p[i * 3 + 2]), view.y(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
            drawPoints(dots, PointMode.Points, TourScene.BAND_COLOURS[band].copy(alpha = 0.85f * fade), strokeWidth = 1.3.dp.toPx())
        }
        val e = scene.edges
        val line = Color.White.copy(alpha = 0.9f)
        for (i in 0 until e.size / 6) {
            val o = i * 6
            drawLine(line, Offset(view.x(e[o], e[o + 2]), view.y(e[o], e[o + 1], e[o + 2])),
                Offset(view.x(e[o + 3], e[o + 5]), view.y(e[o + 3], e[o + 4], e[o + 5])), strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round)
        }
        val badges = TourOverview.spread(scene.stops.map { Vec2(view.x(it.x, it.z), view.y(it.x, it.y, it.z)) }, 21.dp.toPx())
        val style = TextStyle(color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        badges.forEachIndexed { index, b ->
            val centre = Offset(b.x, b.z)
            drawCircle(if (scene.stops[index].level <= 1) Nus.Blue else Nus.Orange, 10.dp.toPx(), centre)
            drawCircle(Color.White, 10.dp.toPx(), centre, style = Stroke(1.5.dp.toPx()))
            val text = measurer.measure("${index + 1}", style)
            drawText(text, topLeft = Offset(centre.x - text.size.width / 2f, centre.y - text.size.height / 2f))
        }
    }
}
