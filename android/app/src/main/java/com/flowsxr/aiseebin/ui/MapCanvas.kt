package com.flowsxr.aiseebin.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.unit.dp
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.positioning.Fix
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Top-down sketch of the graph with the latest fix. x to the right, and
 * graph −z (ARKit "ahead" at the origin) up the screen.
 */
@Composable
fun MapCanvas(map: NavigationMap, fix: Fix?, modifier: Modifier = Modifier, height: androidx.compose.ui.unit.Dp = 280.dp) {
    val edgeColor = MaterialTheme.colorScheme.outline
    val poiColor = MaterialTheme.colorScheme.primary
    val junctionColor = MaterialTheme.colorScheme.outlineVariant
    val textColor = MaterialTheme.colorScheme.onSurface.toArgbInt()
    val youColor = Color(0xFFE5484D)

    Canvas(modifier.fillMaxWidth().height(height)) {
        val points = map.pois.map { it.position } + listOfNotNull(fix?.position)
        if (points.isEmpty()) return@Canvas
        var minX = points.minOf { it.x }; var maxX = points.maxOf { it.x }
        var minZ = points.minOf { it.z }; var maxZ = points.maxOf { it.z }
        val pad = 1.5f
        minX -= pad; maxX += pad; minZ -= pad; maxZ += pad
        val scale = min(size.width / max(maxX - minX, 1f), size.height / max(maxZ - minZ, 1f))
        val offX = (size.width - (maxX - minX) * scale) / 2
        val offY = (size.height - (maxZ - minZ) * scale) / 2
        fun screen(x: Float, z: Float) = Offset(offX + (x - minX) * scale, offY + (z - minZ) * scale)

        val byId = map.pois.associateBy { it.id }
        for (e in map.edges) {
            val a = byId[e.from] ?: continue
            val b = byId[e.to] ?: continue
            drawLine(edgeColor, screen(a.position.x, a.position.z), screen(b.position.x, b.position.z), strokeWidth = 4f)
        }
        val paint = android.graphics.Paint().apply {
            color = textColor
            textSize = 30f
            isAntiAlias = true
        }
        for (p in map.pois) {
            val c = screen(p.position.x, p.position.z)
            if (p.category == PoiCategory.JUNCTION) {
                drawCircle(junctionColor, 6f, c)
            } else {
                drawCircle(poiColor, 12f, c)
                drawContext.canvas.nativeCanvas.drawText(p.name, c.x + 16f, c.y - 10f, paint)
            }
        }
        if (fix != null) {
            val c = screen(fix.position.x, fix.position.z)
            // Heading h faces (sin h, −cos h) in (x, z).
            val dx = sin(fix.heading); val dz = -cos(fix.heading)
            val tip = Offset(c.x + dx * 40f, c.y + dz * 40f)
            val left = Offset(c.x - dz * 16f, c.y + dx * 16f)
            val right = Offset(c.x + dz * 16f, c.y - dx * 16f)
            drawPath(Path().apply {
                moveTo(tip.x, tip.y); lineTo(left.x, left.y); lineTo(right.x, right.y); close()
            }, youColor)
            drawCircle(youColor, 14f, c)
            drawCircle(Color.White, 14f, c, style = Stroke(width = 4f))
        }
    }
}

private fun Color.toArgbInt(): Int =
    android.graphics.Color.argb((alpha * 255).toInt(), (red * 255).toInt(), (green * 255).toInt(), (blue * 255).toInt())
