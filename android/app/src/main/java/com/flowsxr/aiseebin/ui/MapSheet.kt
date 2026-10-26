package com.flowsxr.aiseebin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.flowsxr.aiseebin.map.MapSummary

/** One row of the map switcher. */
data class MapRow(val summary: MapSummary, val selected: Boolean, val detail: String, val usable: Boolean)

/** Design D: the map chip's sheet. 76 dp rows; each says whether it needs a download. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapSheet(rows: List<MapRow>, loading: Boolean, onPick: (String) -> Unit, onRefresh: () -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Ink.Panel,
        dragHandle = { Box(Modifier.padding(top = 14.dp).size(44.dp, 5.dp).background(Ink.Handle, RoundedCornerShape(3.dp))) },
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 28.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Choose map", Modifier.weight(1f), style = plex(700, 24, color = Ink.Light))
                TextAction("Close", Ink.Accent, onDismiss)
            }
            if (rows.isEmpty()) {
                Text(if (loading) "Loading maps…" else "No maps yet. Check the connection, then refresh.", style = plex(400, 16, 1.4f, color = Ink.BodyDark))
                TextAction("Refresh", Ink.Accent, onRefresh)
            }
            rows.forEach { row -> MapRowView(row) { onPick(row.summary.slug) } }
            Row(
                Modifier.fillMaxWidth().background(Ink.Night, RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(AiseeIcons.Info, null, Modifier.size(22.dp), tint = Ink.Accent)
                Text("Only published maps are listed. Drafts stay with staff until they are uploaded.", style = plex(400, 16, 1.4f, color = Ink.BodyDark))
            }
        }
    }
}

@Composable
private fun MapRowView(row: MapRow, onClick: () -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 76.dp)
            .panel(if (row.selected) Ink.RowSelected else Ink.Row, shape, if (row.selected) Ink.Accent else Ink.HairDarkSoft, if (row.selected) 2.dp else 1.dp)
            .clickable(enabled = row.usable, role = Role.RadioButton, onClick = onClick)
            .alpha(if (row.usable) 1f else 0.5f)
            .semantics(mergeDescendants = true) {
                selected = row.selected
                contentDescription = "${row.summary.name}, ${if (row.selected) "selected, " else ""}${row.detail}"
            }
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (row.selected) {
            Box(Modifier.size(28.dp).background(Ink.Accent, CircleShape), contentAlignment = Alignment.Center) {
                Icon(AiseeIcons.Check, null, Modifier.size(16.dp), tint = Ink.Night)
            }
        } else {
            Box(Modifier.size(28.dp).border(2.dp, Ink.DisabledText, CircleShape))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(row.summary.name, style = plex(600, 20, color = Ink.Light))
            Text(row.detail, style = plex(400, 15, color = Ink.Sub))
        }
    }
}
