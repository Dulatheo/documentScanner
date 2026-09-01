package com.dulatheo.documentscanner.ui.edit

enum class EditTool(val label: String, val hint: String) {
    CROP("Crop", "Drag the corners to fit the page"),
    HIGHLIGHT("Highlight", "Tap a line of text to highlight it"),
    ADJUST("Adjust", "Adjust brightness and contrast"),
    TEXT("Text", "Text recognition"),
    SIGN("Sign", "Draw your signature"),
}

/** Signature drawing/placement sub-flow state while the Sign tool is active. */
enum class SignMode { DRAWING, PLACING }

val SignatureColorOptions = listOf(
    "Ink" to "#171614",
    "Blue" to "#2C5EA8",
    "Clay" to "#A4552E",
    "Green" to "#2F6B4F",
)
