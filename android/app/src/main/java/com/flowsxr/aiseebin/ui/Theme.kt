package com.flowsxr.aiseebin.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.flowsxr.aiseebin.R

/**
 * AiSee tokens from the Claude Design "AISEE-BIN Android" file, the same values
 * as iOS v2. Visitor screens (Navigate) are always dark, for contrast in
 * greenhouse sun; staff screens (Home, Settings) are always light.
 */
object Ink {
    // Staff (light)
    val Paper = Color(0xFFF7F5FD)
    val Card = Color(0xFFFFFFFF)
    val Text = Color(0xFF191627)
    val Body = Color(0xFF3E3856)
    val Muted = Color(0xFF5B5570)
    val Faint = Color(0xFF7A7490)
    val Line = Color(0xFFE4E0F0)
    val Divider = Color(0xFFEEEAF6)
    val Chip = Color(0xFFF1EFF7)
    val Primary = Color(0xFF5B3FD1)
    val PrimarySoft = Color(0xFFEFEAFF)
    val PrimarySoftLine = Color(0xFFD9CFFA)
    val OnPrimarySoft = Color(0xFFEDE7FF)
    val Lavender = Color(0xFF9B87E8)
    val GreenBg = Color(0xFFE8F7EF)
    val Green = Color(0xFF0E6B49)
    val AmberBg = Color(0xFFFFF3E0)
    val Amber = Color(0xFF7A4200)
    val SwitchOn = Color(0xFF1FA97A)
    val ErrorBg = Color(0xFFFDEAE8)
    val Error = Color(0xFF9B2A22)

    // Visitor (dark)
    val Night = Color(0xFF0C0B12)
    val Panel = Color(0xFF17151F)
    val ChipDark = Color(0xFF1B1826)
    val Row = Color(0xFF211E2C)
    val RowSelected = Color(0xFF2A2540)
    val Disabled = Color(0xFF1E1B29)
    val DisabledText = Color(0xFF6B6580)
    val Light = Color(0xFFF7F5FD)
    val Sub = Color(0xFFB4AEC6)
    val BodyDark = Color(0xFFDCD7EA)
    val MutedDark = Color(0xFF9E98B5)
    val Accent = Color(0xFFB9A6FF)
    val Talk = Color(0xFF6B4FD8)
    val Handle = Color(0xFF4A4560)
    val Track = Color(0xFF2A2637)
    val Ready = Color(0xFF5EE6A8)
    val ReadyBg = Color(0xFF0F2A1E)
    val ReadyLine = Color(0xFF2C7A56)
    val Wait = Color(0xFFFFC24B)
    val WaitBg = Color(0xFF2C2005)
    val WaitLine = Color(0xFF8A6A17)
    val WaitText = Color(0xFFFFE0A8)
    val HairDark = Color(0x2EF7F5FD) // rgba(247,245,253,.18)
    val HairDarkSoft = Color(0x24F7F5FD) // .14
}

@OptIn(ExperimentalTextApi::class)
private fun plexSans(weight: Int) =
    Font(R.font.ibm_plex_sans, FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))

/** IBM Plex Sans is a variable font; each weight is an instance of it. */
val PlexSans = FontFamily(plexSans(400), plexSans(500), plexSans(600), plexSans(700))
val PlexMono = FontFamily(
    Font(R.font.ibm_plex_mono_regular, FontWeight.Normal),
    Font(R.font.ibm_plex_mono_medium, FontWeight.Medium),
)

/** The design's `font: <weight> <size>/<line>` shorthand, in sp so it follows the system font size. */
fun plex(weight: Int, size: Int, line: Float = 1.2f, mono: Boolean = false, color: Color = Color.Unspecified): TextStyle =
    TextStyle(
        fontFamily = if (mono) PlexMono else PlexSans,
        fontWeight = FontWeight(weight),
        fontSize = size.sp,
        lineHeight = if (line <= 1f) TextUnit.Unspecified else (size * line).sp,
        color = color,
    )

@Composable
fun StaffTheme(content: @Composable () -> Unit) = MaterialTheme(
    colorScheme = lightColorScheme(
        primary = Ink.Primary, onPrimary = Color.White, secondary = Ink.Lavender,
        background = Ink.Paper, onBackground = Ink.Text, surface = Ink.Card, onSurface = Ink.Text,
        surfaceVariant = Ink.Chip, onSurfaceVariant = Ink.Muted, outline = Ink.Line, error = Ink.Error,
        surfaceContainerLow = Ink.Paper, surfaceContainerHigh = Ink.Paper,
    ),
    typography = typography(),
    content = content,
)

@Composable
fun VisitorTheme(content: @Composable () -> Unit) = MaterialTheme(
    colorScheme = darkColorScheme(
        primary = Ink.Accent, onPrimary = Ink.Night, secondary = Ink.Lavender,
        background = Ink.Night, onBackground = Ink.Light, surface = Ink.Panel, onSurface = Ink.Light,
        surfaceVariant = Ink.Row, onSurfaceVariant = Ink.Sub, outline = Ink.Handle, error = Color(0xFFFF8A80),
        surfaceContainerLow = Ink.Panel,
    ),
    typography = typography(),
    content = content,
)

@Composable
private fun typography() = MaterialTheme.typography.run {
    copy(
        displayLarge = displayLarge.copy(fontFamily = PlexSans), displayMedium = displayMedium.copy(fontFamily = PlexSans),
        displaySmall = displaySmall.copy(fontFamily = PlexSans), headlineLarge = headlineLarge.copy(fontFamily = PlexSans),
        headlineMedium = headlineMedium.copy(fontFamily = PlexSans), headlineSmall = headlineSmall.copy(fontFamily = PlexSans),
        titleLarge = titleLarge.copy(fontFamily = PlexSans), titleMedium = titleMedium.copy(fontFamily = PlexSans),
        titleSmall = titleSmall.copy(fontFamily = PlexSans), bodyLarge = bodyLarge.copy(fontFamily = PlexSans),
        bodyMedium = bodyMedium.copy(fontFamily = PlexSans), bodySmall = bodySmall.copy(fontFamily = PlexSans),
        labelLarge = labelLarge.copy(fontFamily = PlexSans), labelMedium = labelMedium.copy(fontFamily = PlexSans),
        labelSmall = labelSmall.copy(fontFamily = PlexSans),
    )
}
