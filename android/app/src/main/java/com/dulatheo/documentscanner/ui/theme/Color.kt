package com.dulatheo.documentscanner.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Design tokens from DESIGN_SPEC.md §3.1. Kept as a flat token object (rather
 * than only inside the Material3 ColorScheme) because several screens need
 * tokens Material3's ColorScheme has no slot for (paper, paperLine, highlight,
 * ink2/ink3 text tiers, hairline "line").
 */
object AppColors {
    // Light
    val LightBg = Color(0xFFF6F4F1)
    val LightSurface = Color(0xFFFFFFFF)
    val LightInk = Color(0xFF171614)
    val LightInk2 = Color(0x99171614) // rgba(23,22,20,.60)
    val LightInk3 = Color(0x5C171614) // rgba(23,22,20,.36)
    val LightLine = Color(0x1A171614) // rgba(23,22,20,.10)
    val LightAccent = Color(0xFFA4552E)
    val LightAccentSoft = Color(0x1AA4552E) // rgba(164,85,46,.10)
    val LightPaper = Color(0xFFFFFDFB)
    val LightPaperLine = Color(0x21171614) // rgba(23,22,20,.13)
    val LightHighlight = Color(0x8CE2B23E) // rgba(226,178,62,.55)

    // Dark
    val DarkBg = Color(0xFF121110)
    val DarkSurface = Color(0xFF1B1A18)
    val DarkInk = Color(0xFFF2F0EC)
    val DarkInk2 = Color(0x99F2F0EC) // rgba(242,240,236,.60)
    val DarkInk3 = Color(0x52F2F0EC) // rgba(242,240,236,.32)
    val DarkLine = Color(0x1FF2F0EC) // rgba(242,240,236,.12)
    val DarkAccent = Color(0xFFDE8E60)
    val DarkAccentSoft = Color(0x26DE8E60) // rgba(222,142,96,.15)
    val DarkPaper = Color(0xFF242120)
    val DarkPaperLine = Color(0x2BF2F0EC) // rgba(242,240,236,.17)
    val DarkHighlight = Color(0x52E2B23E) // rgba(226,178,62,.32)

    // Signature colors (§3.3) — identical in both themes; "Ink" resolves to
    // the current theme's `ink` token at call sites.
    val SignatureBlue = Color(0xFF2C5EA8)
    val SignatureClay = Color(0xFFA4552E)
    val SignatureGreen = Color(0xFF2F6B4F)
}

/** The subset of tokens the app actually threads through composables. */
data class AppColorTokens(
    val bg: Color,
    val surface: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    val line: Color,
    val accent: Color,
    val accentSoft: Color,
    val paper: Color,
    val paperLine: Color,
    val highlight: Color,
)

val LightTokens = AppColorTokens(
    bg = AppColors.LightBg,
    surface = AppColors.LightSurface,
    ink = AppColors.LightInk,
    ink2 = AppColors.LightInk2,
    ink3 = AppColors.LightInk3,
    line = AppColors.LightLine,
    accent = AppColors.LightAccent,
    accentSoft = AppColors.LightAccentSoft,
    paper = AppColors.LightPaper,
    paperLine = AppColors.LightPaperLine,
    highlight = AppColors.LightHighlight,
)

val DarkTokens = AppColorTokens(
    bg = AppColors.DarkBg,
    surface = AppColors.DarkSurface,
    ink = AppColors.DarkInk,
    ink2 = AppColors.DarkInk2,
    ink3 = AppColors.DarkInk3,
    line = AppColors.DarkLine,
    accent = AppColors.DarkAccent,
    accentSoft = AppColors.DarkAccentSoft,
    paper = AppColors.DarkPaper,
    paperLine = AppColors.DarkPaperLine,
    highlight = AppColors.DarkHighlight,
)
