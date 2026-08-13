package com.dulatheo.documentscanner.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The viewfinder/scan-corners glyph used on the empty-state tile and as a
 * capture affordance — four L-shaped corner brackets around a rounded frame. */
@Composable
fun ScanCornersIcon(
    color: Color,
    modifier: Modifier = Modifier,
    size: Dp = 32.dp,
    strokeWidth: Dp = 2.2.dp,
) {
    Canvas(modifier = modifier.size(size)) {
        val armLen = this.size.minDimension * 0.34f
        val inset = this.size.minDimension * 0.08f
        val stroke = Stroke(width = strokeWidth.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
        val w = this.size.width
        val h = this.size.height

        // Top-left
        drawLine(color, Offset(inset, inset + armLen), Offset(inset, inset), stroke.width, stroke.cap)
        drawLine(color, Offset(inset, inset), Offset(inset + armLen, inset), stroke.width, stroke.cap)
        // Top-right
        drawLine(color, Offset(w - inset, inset + armLen), Offset(w - inset, inset), stroke.width, stroke.cap)
        drawLine(color, Offset(w - inset, inset), Offset(w - inset - armLen, inset), stroke.width, stroke.cap)
        // Bottom-left
        drawLine(color, Offset(inset, h - inset - armLen), Offset(inset, h - inset), stroke.width, stroke.cap)
        drawLine(color, Offset(inset, h - inset), Offset(inset + armLen, h - inset), stroke.width, stroke.cap)
        // Bottom-right
        drawLine(color, Offset(w - inset, h - inset - armLen), Offset(w - inset, h - inset), stroke.width, stroke.cap)
        drawLine(color, Offset(w - inset, h - inset), Offset(w - inset - armLen, h - inset), stroke.width, stroke.cap)
    }
}
