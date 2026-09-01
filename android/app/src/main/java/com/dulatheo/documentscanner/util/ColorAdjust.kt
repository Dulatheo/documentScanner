package com.dulatheo.documentscanner.util

/**
 * Brightness/Contrast (DESIGN_SPEC §4.3 "Adjust tool") as a standard 4x5
 * color matrix — contrast scales each channel around the midpoint, then
 * brightness shifts the result. `contrast` is a multiplier (1 = no
 * change); `brightness` is additive, as a fraction of full white (0 = no
 * change), matching the range CoreImage's `CIColorControls` uses on iOS.
 *
 * [zeroToOneDomain] picks which color domain the matrix targets:
 * `androidx.compose.ui.graphics.ColorMatrix` (for a live Compose
 * `ColorFilter`) operates on 0..1 color components, while
 * `android.graphics.ColorMatrix` (used with a `Paint`/`Canvas`/`Bitmap` at
 * export time) operates on 0..255 ones — same matrix shape, the brightness
 * term just needs scaling to whichever domain the caller is in.
 */
fun brightnessContrastMatrixValues(brightness: Float, contrast: Float, zeroToOneDomain: Boolean): FloatArray {
    val scale = if (zeroToOneDomain) 1f else 255f
    val translate = (-0.5f * contrast + 0.5f + brightness) * scale
    return floatArrayOf(
        contrast, 0f, 0f, 0f, translate,
        0f, contrast, 0f, 0f, translate,
        0f, 0f, contrast, 0f, translate,
        0f, 0f, 0f, 1f, 0f,
    )
}
