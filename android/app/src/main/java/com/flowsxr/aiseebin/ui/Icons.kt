package com.flowsxr.aiseebin.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * The design's line icons (24-unit viewBox, round caps), copied from its SVGs.
 * Tinted at the call site; the stroke width is the design's.
 */
object AiseeIcons {
    val ChevronDown = line(2.4f, "M6 9l6 6 6-6")
    val ChevronRight = line(2.4f, "M9 6l6 6-6 6")
    val UpDown = line(2.2f, "M8 10l4-4 4 4M8 14l4 4 4-4")
    val Sliders = line(2f, "M4 7h9M17 7h3M4 17h3M11 17h9", circle(15f, 7f, 2f), circle(9f, 17f, 2f))
    val Check = line(2.6f, "M20 6 9 17l-5-5")
    val Info = line(2f, circle(12f, 12f, 9f), "M12 8v.01M11 12h1v5h1")
    val Mic = line(2f, "M12 2a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V5a3 3 0 0 1 3-3z", "M5 11a7 7 0 0 0 14 0M12 18v4M8 22h8")
    val Pin = line(2.2f, "M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z", circle(12f, 9.5f, 2.5f))
    val Walk = line(2.2f, circle(13f, 4f, 2f), "M11 8l-2 5 3 2 1 5M9 13l-4 2M14 15l4 1")
    val Download = line(2.2f, "M12 3v12M7 10l5 5 5-5M4 20h16")
    val Spinner = line(2.2f, "M12 3v3M12 18v3M3 12h3M18 12h3M6 6l2 2M16 16l2 2M18 6l-2 2M8 16l-2 2")
    val House = line(3f, "M4 11l8-7 8 7v9H4z")
    val Warning = line(2.2f, "M12 4l9 16H3z", "M12 10v4M12 17v.01")
    val Plus = line(2.6f, "M12 5v14M5 12h14")
    val Phone = line(2.6f, "M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z")
    val Glasses = line(2f, circle(6.5f, 14f, 3.5f), circle(17.5f, 14f, 3.5f), "M10 14h4M3 14l1.5-6M21 14l-1.5-6")
    val Camera = line(2f, "M4 7h3l2-3h6l2 3h3v13H4z", circle(12f, 13f, 4f))
    val Code = line(2.2f, "M8 6l-6 6 6 6M16 6l6 6-6 6")
}

/** An SVG circle as a path, so every icon is one stroke style. */
private fun circle(cx: Float, cy: Float, r: Float) =
    "M${cx - r} ${cy}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0"

private fun line(width: Float, vararg paths: String): ImageVector =
    ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f).apply {
        paths.forEach {
            addPath(
                pathData = addPathNodes(it),
                fill = null,
                stroke = SolidColor(Color.Black),
                strokeLineWidth = width,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }.build()
