package com.dulatheo.documentscanner.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.ui.edit.CropOverlay
import com.dulatheo.documentscanner.ui.edit.SignaturePlacement
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import kotlin.math.roundToInt

/**
 * Renders one page image on a `paper`-styled card, with committed
 * highlights and a committed/placed signature drawn live on top (as
 * Compose overlays, not baked into pixels — see util/PageRenderer for the
 * flattened version used at export time). Optionally hosts the interactive
 * Crop overlay, tap-to-highlight, and signature placement drag used by the
 * Edit screen.
 */
@Composable
fun PageCard(
    imagePath: String,
    modifier: Modifier = Modifier,
    ocrLines: List<OcrLine> = emptyList(),
    onLineTap: ((Int) -> Unit)? = null,
    signature: Signature? = null,
    cropCorners: List<Offset>? = null,
    onCropCornersChange: ((List<Offset>) -> Unit)? = null,
    placementRect: Rect? = null,
    onPlacementRectChange: ((Rect) -> Unit)? = null,
    placementStrokes: List<com.dulatheo.documentscanner.data.model.SignatureStroke> = emptyList(),
) {
    val tokens = LocalAppColors.current
    var displaySize by remember { mutableStateOf(IntSize.Zero) }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(tokens.paper)
            .border(1.dp, tokens.line, RoundedCornerShape(4.dp)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onSizeChanged { displaySize = it }
                .let { base ->
                    if (onLineTap != null) {
                        base.pointerInput(ocrLines) {
                            detectTapOnLines(ocrLines, { displaySize }) { index -> onLineTap(index) }
                        }
                    } else base
                },
        ) {
            AsyncImage(
                model = imagePath,
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(),
            )

            if (ocrLines.any { it.highlighted } && displaySize.width > 0) {
                Canvas(modifier = Modifier.matchParentSize()) {
                    val highlightColor = tokens.highlight
                    for (line in ocrLines) {
                        if (!line.highlighted) continue
                        drawRect(
                            color = highlightColor,
                            topLeft = Offset(line.left * size.width, line.top * size.height),
                            size = Size(
                                (line.right - line.left) * size.width,
                                (line.bottom - line.top) * size.height,
                            ),
                        )
                    }
                }
            }

            if (signature != null && placementRect == null && displaySize.width > 0) {
                val rect = Rect(
                    signature.x * displaySize.width,
                    signature.y * displaySize.height,
                    (signature.x + signature.width) * displaySize.width,
                    (signature.y + signature.height) * displaySize.height,
                )
                SignaturePlacement(
                    strokes = signature.strokes,
                    rect = rect,
                    onRectChange = null,
                    accentColor = tokens.accent,
                )
            }

            if (cropCorners != null && onCropCornersChange != null && displaySize.width > 0) {
                CropOverlay(
                    corners = cropCorners,
                    onCornersChange = onCropCornersChange,
                    boxSizePx = displaySize,
                    accentColor = tokens.accent,
                    modifier = Modifier.matchParentSize(),
                )
            }

            if (placementRect != null && onPlacementRectChange != null) {
                SignaturePlacement(
                    strokes = placementStrokes,
                    rect = placementRect,
                    onRectChange = onPlacementRectChange,
                    accentColor = tokens.accent,
                )
            }
        }
    }
}

private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.detectTapOnLines(
    lines: List<OcrLine>,
    getDisplaySize: () -> IntSize,
    onTap: (Int) -> Unit,
) {
    detectTapGestures { offset ->
        val displaySize = getDisplaySize()
        if (displaySize.width == 0 || displaySize.height == 0) return@detectTapGestures
        val nx = offset.x / displaySize.width
        val ny = offset.y / displaySize.height
        val idx = lines.indexOfFirst { nx in it.left..it.right && ny in it.top..it.bottom }
        if (idx >= 0) onTap(idx)
    }
}
