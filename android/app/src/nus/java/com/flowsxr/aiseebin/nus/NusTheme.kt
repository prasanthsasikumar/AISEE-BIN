package com.flowsxr.aiseebin.nus

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.foundation.LocalIndication
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** NUS colours for the tour app (AISEE-BIN's tokens are untouched). The same values as iOS `NUS`. */
object Nus {
    /** The guide's name on screen. One place, so the mascot can be renamed. */
    const val MASCOT = "SoCCat"
    val Blue = Color(0xFF003D7C)
    val Orange = Color(0xFFEF7C00)
    val Ink = Color(0xFF14213D)
    val InkSecondary = Color(0xFF4A5876)
    val Canvas = Color(0xFFF5F7FB)
    val Card = Color.White
    val Ok = Color(0xFF1F9D6B)
    val Warn = Color(0xFFC77700)
}

/** Big rounded action button (iOS `NUSButtonStyle`). */
@Composable
fun NusButton(text: String, fill: Color, onClick: () -> Unit, modifier: Modifier = Modifier,
              icon: ImageVector? = null, enabled: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 64.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(fill.copy(alpha = if (!enabled) 0.35f else if (pressed) 0.8f else 1f))
            .clickable(interaction, LocalIndication.current, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val ink = Color.White.copy(alpha = if (enabled) 1f else 0.6f)
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(10.dp))
        }
        Text(text, color = ink, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}

/** Filled icons on a 24-unit grid (Material Symbols' shapes), tinted at the call site. */
object NusIcons {
    val VolumeUp = filled("M3,9v6h4l5,5V4L7,9H3zM16.5,12c0,-1.77 -1.02,-3.29 -2.5,-4.03v8.05c1.48,-0.73 2.5,-2.25 2.5,-4.02z" +
        "M14,3.23v2.06c2.89,0.86 5,3.54 5,6.71s-2.11,5.85 -5,6.71v2.06c4.01,-0.91 7,-4.49 7,-8.77s-2.99,-7.86 -7,-8.77z")
    val VolumeOff = filled("M16.5,12c0,-1.77 -1.02,-3.29 -2.5,-4.03v2.21l2.45,2.45c0.03,-0.2 0.05,-0.41 0.05,-0.63z" +
        "M19,12c0,0.94 -0.2,1.82 -0.54,2.64l1.51,1.51C20.63,14.91 21,13.5 21,12c0,-4.28 -2.99,-7.86 -7,-8.77v2.06c2.89,0.86 5,3.54 5,6.71z" +
        "M4.27,3L3,4.27 7.73,9H3v6h4l5,5v-6.73l4.25,4.25c-0.67,0.52 -1.42,0.93 -2.25,1.18v2.06c1.38,-0.31 2.63,-0.95 3.69,-1.81L19.73,21 21,19.73l-9,-9L4.27,3z" +
        "M12,4L9.91,6.09 12,8.18V4z")
    val Walk = filled("M13.5,5.5c1.1,0 2,-0.9 2,-2s-0.9,-2 -2,-2 -2,0.9 -2,2 0.9,2 2,2z" +
        "M9.8,8.9L7,23h2.1l1.8,-8 2.1,2v6h2v-7.5l-2.1,-2 0.6,-3C14.8,12 16.8,13 19,13v-2c-1.9,0 -3.5,-1 -4.3,-2.4l-1,-1.6" +
        "c-0.4,-0.6 -1,-1 -1.7,-1 -0.3,0 -0.5,0.1 -0.8,0.1L6,8.3V13h2V9.6l1.8,-0.7")
    val List = filled("M3,13h2v-2H3v2zM3,17h2v-2H3v2zM3,9h2V7H3v2zM7,13h14v-2H7v2zM7,17h14v-2H7v2zM7,7v2h14V7H7z")
    val Close = filled("M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z")
    val Pin = filled("M12,2C8.13,2 5,5.13 5,9c0,5.25 7,13 7,13s7,-7.75 7,-13c0,-3.87 -3.13,-7 -7,-7z" +
        "M12,11.5c-1.38,0 -2.5,-1.12 -2.5,-2.5s1.12,-2.5 2.5,-2.5 2.5,1.12 2.5,2.5 -1.12,2.5 -2.5,2.5z")
    val Stairs = filled("M19,3H5C3.9,3 3,3.9 3,5v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V5C21,3.9 20.1,3 19,3z" +
        "M18,8h-2.42v3.33H13v3.33h-2.58V18H6v-2h2.42v-3.33H11V9.33h2.58V6H18V8z")
    /** Bare steps, for the badge on the small map. */
    val Steps = filled("M20,4v3h-4v4h-4v4H8v4H3v-3h2v-4h4V8h4V4h7z")
    val Lift = filled("M16,17.01V10h-2v7.01h-3L15,21l4,-3.99h-3zM9,3L5,6.99h3V14h2V6.99h3L9,3z")
    val Flag = filled("M14.4,6L14,4H5v17h2v-7h5.6l0.4,2h7V6z")
    val Skip = filled("M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z")
    val Camera = filled("M12,8.8a3.2,3.2 0,1 0,0 6.4a3.2,3.2 0,1 0,0 -6.4z" +
        "M9,2L7.17,4H4c-1.1,0 -2,0.9 -2,2v12c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6c0,-1.1 -0.9,-2 -2,-2h-3.17L15,2H9z" +
        "M12,17c-2.76,0 -5,-2.24 -5,-5s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5z")
    /** Points up; rotated for turns and for "tilt down". */
    val ArrowUp = filled("M4,12l1.41,1.41L11,7.83V20h2V7.83l5.58,5.59L20,12l-8,-8 -8,8z")
    val TurnLeft = filled("M6.83,11l1.58,1.59L7,14 3,10l4,-4 1.41,1.41L6.83,9H15c2.21,0 4,1.79 4,4v7h-2v-7c0,-1.1 -0.9,-2 -2,-2H6.83z")
    val TurnRight = filled("M17.17,11l-1.58,1.59L17,14l4,-4 -4,-4 -1.41,1.41L17.17,9H9c-2.21,0 -4,1.79 -4,4v7h2v-7c0,-1.1 0.9,-2 2,-2h8.17z")
    val UTurn = filled("M18,9v12h-2V9c0,-2.21 -1.79,-4 -4,-4S8,6.79 8,9v4.17l1.59,-1.59L11,13l-4,4 -4,-4 1.41,-1.41L6,13.17V9c0,-3.31 2.69,-6 6,-6s6,2.69 6,6z")
    val ArrowCircle = filled("M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM13,16h-2v-4H8l4,-4 4,4h-3v4z")
    val Check = filled("M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z")

    private fun filled(path: String): ImageVector =
        ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .addPath(pathData = addPathNodes(path), fill = SolidColor(Color.Black))
            .build()
}
