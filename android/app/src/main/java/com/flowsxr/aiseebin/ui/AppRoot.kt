package com.flowsxr.aiseebin.ui

import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flowsxr.aiseebin.AppModel
import com.flowsxr.aiseebin.glasses.GlassesController
import com.flowsxr.aiseebin.glasses.Link

private enum class Page { NAVIGATE, HOME, SETTINGS, DEVELOPER }

/**
 * The app's pages and the platform layer around them: system back (design
 * "System back"), the map sheet, dialogs, status-bar icon colour.
 */
@Composable
fun AppRoot(model: AppModel, permissionsGranted: Boolean, cameraGranted: Boolean, requestPermissions: () -> Unit, openBluetoothSettings: () -> Unit, close: () -> Unit) {
    val staff by model.staff.collectAsStateWithLifecycle()
    val m by model.maps.collectAsStateWithLifecycle()
    val g by model.glasses.state.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf(if (staff) Page.HOME else Page.NAVIGATE) }
    var settingsFrom by rememberSaveable { mutableStateOf(Page.NAVIGATE) }
    var mapSheet by rememberSaveable { mutableStateOf(false) }
    var dismissedError by rememberSaveable { mutableStateOf<String?>(null) }
    var askedPermissions by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current

    val fiveTaps = remember { FiveTaps(tick = model.haptics::tick, unlocked = { model.haptics.confirm(); model.setStaff(true); page = Page.HOME }) }
    fun openSettings() { settingsFrom = page; page = Page.SETTINGS }

    // Back: visitor root asks twice and never leads into staff screens.
    var lastBack by remember { mutableStateOf(0L) }
    val atRoot = page == Page.HOME || (page == Page.NAVIGATE && !staff)
    BackHandler {
        when (page) {
            Page.DEVELOPER -> page = Page.SETTINGS
            Page.SETTINGS -> page = settingsFrom
            Page.NAVIGATE, Page.HOME -> if (!atRoot) page = Page.HOME else {
                val now = System.currentTimeMillis()
                if (now - lastBack < 2_000) close()
                else { lastBack = now; Toast.makeText(context, "Press back again to close", Toast.LENGTH_SHORT).show() }
            }
        }
    }

    val dark = page == Page.NAVIGATE
    val view = LocalView.current
    SideEffect {
        (view.context as? Activity)?.window?.let { w ->
            WindowCompat.getInsetsController(w, view).apply { isAppearanceLightStatusBars = !dark; isAppearanceLightNavigationBars = !dark }
        }
    }

    val source by model.source.collectAsStateWithLifecycle()
    val chip = chipState(model, m)
    Box(Modifier.fillMaxSize().background(if (dark) Ink.Night else Ink.Paper).safeDrawingPadding()) {
        when (page) {
            Page.NAVIGATE -> VisitorTheme {
                NavigateScreen(model, chip, cameraGranted,
                    onAllowCamera = requestPermissions,
                    onLogo = { if (staff) page = Page.HOME else fiveTaps.tap() },
                    onChip = { mapSheet = true },
                    onSettings = ::openSettings,
                    onConnect = {
                        // The last glasses if known, then any paired glasses, else the picker.
                        model.glasses.reconnectLast()
                        if (model.glasses.state.value.link == Link.DISCONNECTED) {
                            model.glasses.bondedDevices().firstOrNull { GlassesController.looksLikeGlasses(it.name) }
                                ?.let { model.glasses.connect(it.address, it.name) } ?: openSettings()
                        }
                    })
            }
            Page.HOME -> StaffTheme {
                HomeScreen(model,
                    onNavigate = { s -> if (s.slug != m.selectedSlug) model.selectMap(s.slug); page = Page.NAVIGATE },
                    onSettings = ::openSettings)
            }
            Page.SETTINGS -> StaffTheme {
                SettingsScreen(model, staff,
                    onDone = { page = settingsFrom },
                    onDeveloper = { page = Page.DEVELOPER },
                    onExitStaff = { model.setStaff(false); page = Page.NAVIGATE },
                    openBluetoothSettings = openBluetoothSettings)
            }
            Page.DEVELOPER -> StaffTheme { DeveloperScreen(model, onBack = { page = Page.SETTINGS }) }
        }
    }

    if (mapSheet) VisitorTheme {
        MapSheet(
            rows = m.available.map { s ->
                val usable = s.immersalMapIds.isNotEmpty()
                MapRow(s, s.slug == m.selectedSlug, when {
                    !usable -> "no glasses alignment yet"
                    model.isCached(s.immersalMapIds) -> "v${s.version} · ready offline"
                    else -> "v${s.version} · downloads when picked"
                }, usable)
            },
            loading = m.loading,
            onPick = { slug -> model.haptics.confirm(); if (slug != m.selectedSlug) model.selectMap(slug); mapSheet = false },
            onRefresh = model::refreshMaps,
            onDismiss = { mapSheet = false },
        )
    }

    if ((!permissionsGranted || (!cameraGranted && source == AppModel.PositionSource.PHONE)) && !askedPermissions) {
        AiseeDialog(
            title = "Allow nearby devices",
            body = "AISEE-BIN uses the camera to find where you are, and Bluetooth, nearby-devices and location permission to reach the glasses.",
            confirm = "Allow", onConfirm = { askedPermissions = true; requestPermissions() },
            dismiss = "Not now", onDismiss = { askedPermissions = true },
            warning = false,
        )
    }

    // Errors the user should see once: glasses or video failures (glasses source only), and a map that would not load.
    val mapError = m.status?.takeIf { it.startsWith("Could not") }
    val error = g.error?.takeIf { source == AppModel.PositionSource.GLASSES } ?: mapError
    LaunchedEffect(error) { if (error == null) dismissedError = null }
    if (error != null && error != dismissedError) {
        AiseeDialog(
            title = "Something went wrong",
            body = error,
            confirm = "Try again",
            onConfirm = {
                dismissedError = error
                if (error == mapError) { m.selectedSlug?.let(model::selectMap) ?: model.refreshMaps() }
                else if (g.link == Link.READY) model.startCamera() else model.glasses.reconnectLast()
            },
            dismiss = "OK", onDismiss = { dismissedError = error },
        )
    }
}

private fun chipState(model: AppModel, m: com.flowsxr.aiseebin.MapState): ChipState {
    val name = m.map?.name ?: m.available.firstOrNull { it.slug == m.selectedSlug }?.name ?: "No map"
    val version = m.available.firstOrNull { it.slug == m.selectedSlug }?.version
    val ready = m.map != null && !m.map.alignment?.mapIds.isNullOrEmpty() && !m.loading && !m.downloading
    val state = when {
        m.loading -> "loading"
        m.downloading -> "downloading"
        ready -> "ready"
        else -> "not ready"
    }
    return ChipState(
        name = name,
        detail = "Navigate" + (version?.let { " · map v$it" } ?: ""),
        ready = ready,
        spoken = "$name map" + (version?.let { ", version $it" } ?: "") + ", $state",
    )
}

/**
 * Design 11: icon, centred headline, left-aligned body, actions bottom-right
 * with the confirming one last. Back or a tap outside counts as [onDismiss].
 */
@Composable
fun AiseeDialog(title: String, body: String, confirm: String, onConfirm: () -> Unit, dismiss: String, onDismiss: () -> Unit, warning: Boolean = true) {
    StaffTheme {
        AlertDialog(
            onDismissRequest = onDismiss,
            containerColor = Ink.Paper,
            icon = {
                Box(Modifier.size(52.dp).background(if (warning) Ink.ErrorBg else Ink.PrimarySoft, CircleShape), contentAlignment = Alignment.Center) {
                    Icon(if (warning) AiseeIcons.Warning else AiseeIcons.Glasses, null, Modifier.size(28.dp), tint = if (warning) Ink.Error else Ink.Primary)
                }
            },
            title = { Text(title, style = plex(700, 24, 1.25f, color = Ink.Text), textAlign = TextAlign.Center) },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(body, style = plex(400, 16, 1.5f, color = Ink.Body)) } },
            dismissButton = { TextButton(onClick = onDismiss) { Text(dismiss, style = plex(600, 17, color = Ink.Body)) } },
            confirmButton = {
                androidx.compose.material3.Button(onClick = onConfirm, colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = Ink.Primary)) {
                    Text(confirm, style = plex(600, 17, color = androidx.compose.ui.graphics.Color.White))
                }
            },
        )
    }
}
