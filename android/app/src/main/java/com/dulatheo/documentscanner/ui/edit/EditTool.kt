package com.dulatheo.documentscanner.ui.edit

import androidx.annotation.StringRes
import com.dulatheo.documentscanner.R

/** [labelRes]/[hintRes] are resource ids, not resolved strings — an enum's
 * constructor runs at class-load time, long before any `@Composable`
 * context exists to call `stringResource` from, so callers resolve these
 * themselves (e.g. `Text(stringResource(tool.labelRes))`) from within their
 * own composable body. */
enum class EditTool(@StringRes val labelRes: Int, @StringRes val hintRes: Int) {
    CROP(R.string.edit_tool_crop_label, R.string.edit_tool_crop_hint),
    ADJUST(R.string.edit_tool_adjust_label, R.string.edit_tool_adjust_hint),
    COMMENT(R.string.edit_tool_comment_label, R.string.edit_tool_comment_hint),
    TEXT(R.string.edit_tool_text_label, R.string.edit_tool_text_hint),
    SIGN(R.string.edit_tool_sign_label, R.string.edit_tool_sign_hint),
}

/** Signature drawing/placement sub-flow state while the Sign tool is active. */
enum class SignMode { DRAWING, PLACING }

val SignatureColorOptions = listOf(
    "Ink" to "#171614",
    "Blue" to "#2C5EA8",
    "Clay" to "#A4552E",
    "Green" to "#2F6B4F",
)
