package com.flowsxr.aiseebin.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.AppModel
import com.flowsxr.aiseebin.map.MapSummary

/**
 * Design A: the staff start screen. Every map says where it lives and offers
 * its next action. Android can't make or edit maps yet, so New map, Explore and
 * Edit are shown but marked as coming.
 */
@Composable
fun HomeScreen(model: AppModel, onLogo: () -> Unit, onNavigate: (MapSummary) -> Unit, onSettings: () -> Unit) {
    val m by model.maps.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().background(Ink.Paper)) {
        StaffHeader("Maps", "Staff mode", onLogo = onLogo) {
            HeaderButton(AiseeIcons.Sliders, "Settings", dark = false, onClick = onSettings)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            NewMapCard()
            GroupLabel("Your maps")
            if (m.available.isEmpty()) {
                StaffCard {
                    Text(m.status ?: if (m.loading) "Loading maps…" else "No maps on the server.", style = plex(400, 16, 1.4f, color = Ink.Body))
                    StaffButton("Refresh", StaffButtonStyle.PLAIN, Modifier.fillMaxWidth(), onClick = model::refreshMaps)
                }
            }
            m.available.forEach { s ->
                val inUse = s.slug == m.selectedSlug
                val cached = model.isCached(s.immersalMapIds)
                MapCard(s, inUse, cached, downloading = inUse && m.downloading,
                    onNavigate = { onNavigate(s) },
                    onGet = { if (inUse) model.downloadMaps() else model.selectMap(s.slug) })
            }
            m.status?.takeIf { m.available.isNotEmpty() }?.let { Text(it, style = plex(400, 14, 1.4f, color = Ink.Muted)) }
        }
    }
}

@Composable
private fun NewMapCard() {
    Row(
        Modifier.fillMaxWidth().background(Ink.Primary, RoundedCornerShape(24.dp)).alpha(0.55f).padding(horizontal = 20.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(52.dp).background(Ink.Paper, CircleShape), contentAlignment = Alignment.Center) {
            Icon(AiseeIcons.Plus, null, Modifier.size(28.dp), tint = Ink.Primary)
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("New map", style = plex(700, 22, color = Color.White))
            Text("Coming to Android. Make maps on the iPhone for now.", style = plex(400, 15, 1.3f, color = Ink.OnPrimarySoft))
        }
    }
}

@Composable
private fun MapCard(s: MapSummary, inUse: Boolean, cached: Boolean, downloading: Boolean, onNavigate: () -> Unit, onGet: () -> Unit) {
    val usable = s.immersalMapIds.isNotEmpty()
    StaffCard(highlighted = inUse) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.name, style = plex(600, 19, color = Ink.Text), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    "v${s.version} · " + when {
                        !usable -> "no glasses alignment"
                        downloading -> "downloading…"
                        cached -> "on this phone"
                        else -> "on server"
                    },
                    style = plex(400, 13, mono = true, color = Ink.Muted),
                )
            }
            if (inUse) Badge("In use", good = true)
        }
        if (usable) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StaffButton("Navigate", StaffButtonStyle.DARK, Modifier.weight(1f), onClick = onNavigate)
                if (!cached) StaffButton(if (downloading) "Getting…" else "Get", StaffButtonStyle.PLAIN, Modifier.weight(1f),
                    enabled = !downloading, icon = AiseeIcons.Download, onClick = onGet)
                else StaffButton("Explore", StaffButtonStyle.PLAIN, Modifier.weight(1f), enabled = false) {}
                StaffButton("Edit", StaffButtonStyle.SOFT, Modifier.weight(1f), enabled = false) {}
            }
        }
    }
}
