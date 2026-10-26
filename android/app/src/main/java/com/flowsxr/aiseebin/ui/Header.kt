package com.flowsxr.aiseebin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** What the map chip shows: the map, the mode, and whether it is ready. */
data class ChipState(val name: String, val detail: String, val ready: Boolean, val spoken: String)

/**
 * Five taps within three seconds on the visitor logo unlock staff mode, with a
 * tick on taps 3–5 (design: "Staff unlock"). There is no hint on purpose.
 */
class FiveTaps(private val tick: () -> Unit, private val unlocked: () -> Unit) {
    private val taps = ArrayDeque<Long>()

    fun tap(now: Long = System.currentTimeMillis()) {
        taps.addLast(now)
        while (taps.isNotEmpty() && now - taps.first() > WINDOW_MS) taps.removeFirst()
        if (taps.size >= 3) tick()
        if (taps.size >= 5) { taps.clear(); unlocked() }
    }

    companion object { const val WINDOW_MS = 3_000L }
}

/** The shared visitor header: logo, map chip, settings. */
@Composable
fun VisitorHeader(staff: Boolean, chip: ChipState, onLogo: () -> Unit, onChip: () -> Unit, onSettings: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // The logo has no hint text (TalkBack), and gives no ripple to visitors.
        LogoTile(staff, Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() }, indication = null,
            onClick = onLogo,
        ).semantics { contentDescription = "AiSee" })
        Row(
            Modifier.weight(1f).height(52.dp)
                .panel(Ink.ChipDark, CircleShape, Ink.HairDark)
                .clickable(role = Role.Button, onClickLabel = "change map", onClick = onChip)
                .semantics(mergeDescendants = true) { contentDescription = chip.spoken }
                .padding(start = 16.dp, end = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(10.dp).background(if (chip.ready) Ink.Ready else Ink.Wait, CircleShape))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(chip.name, style = plex(600, 17, color = Ink.Light), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(chip.detail, style = plex(500, 12, mono = true, color = Ink.Sub), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Icon(AiseeIcons.ChevronDown, null, Modifier.size(20.dp), tint = Ink.Sub)
        }
        onSettings?.let { HeaderButton(AiseeIcons.Sliders, "Settings", dark = true, onClick = it) }
    }
}

/** The staff header: logo (with badge), title and subtitle, and a trailing action. */
@Composable
fun StaffHeader(title: String, subtitle: String?, onLogo: (() -> Unit)?, trailing: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        LogoTile(true, if (onLogo != null) Modifier.clickable(onClickLabel = "go home", onClick = onLogo) else Modifier)
        Column(Modifier.weight(1f).padding(start = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = plex(700, if (subtitle == null) 22 else 24, color = Ink.Text))
            subtitle?.let { Text(it, style = plex(500, 13, color = Ink.Muted)) }
        }
        trailing()
    }
}

/** "Done" / "Close" text actions in staff headers and sheets. */
@Composable
fun TextAction(label: String, color: Color = Ink.Primary, onClick: () -> Unit) {
    Text(
        label,
        Modifier.clickable(role = Role.Button, onClick = onClick).padding(horizontal = 6.dp, vertical = 12.dp),
        style = plex(600, 18, color = color),
    )
}
