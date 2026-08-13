package com.dulatheo.documentscanner.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import com.google.accompanist.systemuicontroller.rememberSystemUiController

/** CompositionLocal carrying the raw design tokens (§3.1) that Material3's
 * ColorScheme has no dedicated slot for (paper, paperLine, highlight, the
 * ink2/ink3 text tiers, hairline "line"). */
val LocalAppColors = compositionLocalOf { LightTokens }

@Composable
fun DocumentScannerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val tokens = if (darkTheme) DarkTokens else LightTokens

    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = tokens.accent,
            onPrimary = Color.White,
            secondary = tokens.accent,
            background = tokens.bg,
            onBackground = tokens.ink,
            surface = tokens.surface,
            onSurface = tokens.ink,
            surfaceVariant = tokens.paper,
            onSurfaceVariant = tokens.ink2,
            outline = tokens.line,
            error = Color(0xFFCF6679),
        )
    } else {
        lightColorScheme(
            primary = tokens.accent,
            onPrimary = Color.White,
            secondary = tokens.accent,
            background = tokens.bg,
            onBackground = tokens.ink,
            surface = tokens.surface,
            onSurface = tokens.ink,
            surfaceVariant = tokens.paper,
            onSurfaceVariant = tokens.ink2,
            outline = tokens.line,
            error = Color(0xFFB3261E),
        )
    }

    val systemUiController = rememberSystemUiController()
    systemUiController.setStatusBarColor(color = tokens.bg, darkIcons = !darkTheme)
    systemUiController.setNavigationBarColor(color = tokens.bg, darkIcons = !darkTheme)

    CompositionLocalProvider(LocalAppColors provides tokens) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AppTypography,
            content = content,
        )
    }
}
