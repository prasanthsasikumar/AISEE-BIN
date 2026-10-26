package com.flowsxr.aiseebin.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.flowsxr.aiseebin.R

/** The design draws outlines as inset box-shadows; a border of the same width reads the same. */
fun Modifier.panel(color: Color, shape: Shape, line: Color? = null, lineWidth: Dp = 1.5.dp): Modifier =
    clip(shape).background(color, shape).let { if (line != null) it.border(lineWidth, line, shape) else it }

/** The lavender AiSee tile; [staff] adds the house badge. */
@Composable
fun LogoTile(staff: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(52.dp)) {
        Box(Modifier.size(52.dp).panel(Ink.Lavender, RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
            Image(painterResource(R.drawable.aisee_logo_white), contentDescription = null, Modifier.width(30.dp))
        }
        if (staff) {
            Box(
                Modifier.align(Alignment.BottomEnd).offset(4.dp, 4.dp).size(22.dp)
                    .border(2.dp, Ink.Paper, CircleShape).padding(2.dp).background(Ink.Text, CircleShape),
                contentAlignment = Alignment.Center,
            ) { Icon(AiseeIcons.House, null, Modifier.size(11.dp), tint = Color.White) }
        }
    }
}

/** A square header button (settings, back). */
@Composable
fun HeaderButton(icon: ImageVector, label: String, dark: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(52.dp)
            .panel(if (dark) Ink.ChipDark else Ink.Card, RoundedCornerShape(16.dp), if (dark) Ink.HairDark else Ink.Line)
            .clickable(onClickLabel = label, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, Modifier.size(24.dp), tint = if (dark) Ink.BodyDark else Ink.Body) }
}

enum class Tone { READY, WAIT, NEUTRAL }

/** The state pill under the header. A live region, so TalkBack reads every change. */
@Composable
fun StatePill(text: String, tone: Tone, pulse: Boolean = false) {
    val (bg, line, fg) = when (tone) {
        Tone.READY -> Triple(Ink.ReadyBg, Ink.ReadyLine, Ink.Ready)
        Tone.WAIT -> Triple(Ink.WaitBg, Ink.WaitLine, Ink.Wait)
        Tone.NEUTRAL -> Triple(Ink.ChipDark, Ink.HairDark, Ink.BodyDark)
    }
    Row(
        Modifier.panel(bg, CircleShape, line).padding(start = 14.dp, end = 18.dp, top = 12.dp, bottom = 12.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (tone == Tone.READY) Icon(AiseeIcons.Check, null, Modifier.size(22.dp), tint = fg)
        else PulseDot(fg, pulse)
        Text(text, style = plex(600, 19, color = fg))
    }
}

@Composable
private fun PulseDot(color: Color, pulse: Boolean) {
    // Reduce Motion: the system's animator scale of 0 ("Remove animations") drops the ring.
    val context = LocalContext.current
    val animate = pulse && remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
    }
    Box(Modifier.size(16.dp), contentAlignment = Alignment.Center) {
        if (animate) {
            val t = rememberInfiniteTransition(label = "pulse")
            val p by t.animateFloat(0f, 1f, infiniteRepeatable(tween(1800), RepeatMode.Restart), label = "p")
            val k = (p / 0.7f).coerceAtMost(1f)
            Box(Modifier.size(16.dp).scale(1f + 0.6f * k).graphicsLayer { alpha = 0.55f * (1f - k) }.background(color, CircleShape))
        }
        Box(Modifier.size(16.dp).background(color, CircleShape))
    }
}

/** The hint banner at the bottom of the camera area. Assertive when [urgent]. */
@Composable
fun HintBanner(text: String, tone: Tone, modifier: Modifier = Modifier, urgent: Boolean = false) {
    val wait = tone == Tone.WAIT
    Row(
        modifier.fillMaxWidth()
            .panel(if (wait) Color(0xEB2C2005) else Color(0xE617151F), RoundedCornerShape(20.dp), if (wait) Ink.WaitLine else Color(0x1FF7F5FD), 1.dp)
            .padding(horizontal = 18.dp, vertical = 16.dp)
            .semantics(mergeDescendants = true) { liveRegion = if (urgent) LiveRegionMode.Assertive else LiveRegionMode.Polite },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(AiseeIcons.Info, null, Modifier.size(24.dp), tint = if (wait) Ink.Wait else Ink.Accent)
        Text(text, style = plex(400, 17, 1.35f, color = if (wait) Ink.WaitText else Ink.BodyDark))
    }
}

/** A 72 dp visitor action. Disabled, it relabels itself to the reason. */
@Composable
fun BigButton(label: String, icon: ImageVector?, enabled: Boolean, modifier: Modifier = Modifier, filled: Boolean = false, onClick: () -> Unit) {
    val bg = when { !enabled -> Ink.Disabled; filled -> Ink.Light; else -> Ink.Row }
    val fg = when { !enabled -> Ink.DisabledText; filled -> Ink.Night; else -> Ink.Light }
    Row(
        modifier.heightIn(min = 72.dp).fillMaxWidth()
            .panel(bg, RoundedCornerShape(22.dp), if (filled && enabled) null else Ink.HairDarkSoft, 1.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
    ) {
        icon?.let { Icon(it, null, Modifier.size(24.dp), tint = fg) }
        Text(label, style = plex(600, 20, color = fg), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The staff screens' uppercase group label. */
@Composable
fun GroupLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), modifier.padding(start = 4.dp, top = 8.dp), style = plex(600, 13, color = Ink.Muted).copy(letterSpacing = androidx.compose.ui.unit.TextUnit(0.12f, androidx.compose.ui.unit.TextUnitType.Em)))
}

/** A white staff card. */
@Composable
fun StaffCard(modifier: Modifier = Modifier, highlighted: Boolean = false, padding: Dp = 16.dp, content: @Composable () -> Unit) {
    Column(
        modifier.fillMaxWidth().panel(Ink.Card, RoundedCornerShape(if (padding > 0.dp) 22.dp else 20.dp), if (highlighted) Ink.Lavender else Ink.Line, if (highlighted) 2.dp else 1.5.dp)
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) { content() }
}

/** A 60 dp settings row; [trailing] holds a value, switch or chevron. */
@Composable
fun SettingRow(title: String, subtitle: String? = null, divider: Boolean = false, onClick: (() -> Unit)? = null, trailing: @Composable RowScope.() -> Unit = {}) {
    Column {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 60.dp)
                .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it }
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = plex(500, 17, color = Ink.Text))
                subtitle?.let { Text(it, style = plex(400, 13, 1.3f, color = Ink.Muted)) }
            }
            trailing()
        }
        if (divider) Box(Modifier.fillMaxWidth().padding(horizontal = 0.dp).heightIn(min = 1.5.dp).background(Ink.Divider))
    }
}

/** Staff buttons: 48 dp, in the three weights Home uses. */
enum class StaffButtonStyle { DARK, PLAIN, SOFT, PRIMARY }

@Composable
fun StaffButton(label: String, style: StaffButtonStyle, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    val (bg, fg, line) = when (style) {
        StaffButtonStyle.DARK -> Triple(Ink.Text, Color.White, null)
        StaffButtonStyle.PLAIN -> Triple(Ink.Chip, Ink.Text, Ink.Line)
        StaffButtonStyle.SOFT -> Triple(Ink.PrimarySoft, Ink.Primary, Ink.PrimarySoftLine)
        StaffButtonStyle.PRIMARY -> Triple(Ink.Primary, Color.White, null)
    }
    Row(
        modifier.heightIn(min = 48.dp).panel(bg, RoundedCornerShape(14.dp), line)
            .graphicsLayer { alpha = if (enabled) 1f else 0.4f }
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        icon?.let { Icon(it, null, Modifier.size(18.dp), tint = fg) }
        Text(label, style = plex(600, 16, color = fg), maxLines = 1)
    }
}

/** A small status badge on a Home map card. */
@Composable
fun Badge(text: String, good: Boolean) {
    val bg = if (good) Ink.GreenBg else Ink.AmberBg
    val fg = if (good) Ink.Green else Ink.Amber
    Row(
        Modifier.panel(bg, CircleShape).padding(horizontal = 9.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(if (good) AiseeIcons.Check else AiseeIcons.Phone, null, Modifier.size(12.dp), tint = fg)
        Text(text, style = plex(600, 12, color = fg))
    }
}
