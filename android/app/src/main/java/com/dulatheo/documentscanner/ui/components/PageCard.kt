package com.dulatheo.documentscanner.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.ui.edit.CropOverlay
import com.dulatheo.documentscanner.ui.edit.SignaturePlacement
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import com.dulatheo.documentscanner.util.brightnessContrastMatrixValues
import kotlin.math.roundToInt

/**
 * Renders one page image on a `paper`-styled card, with committed
 * highlights (from a document highlighted before the Highlight tool was
 * removed — still rendered for backward compatibility, just not
 * creatable anymore) and a committed/placed signature drawn live on top
 * (as Compose overlays, not baked into pixels — see util/PageRenderer for
 * the flattened version used at export time). Optionally hosts the
 * interactive Crop overlay and signature placement drag used by the Edit
 * screen.
 */
@Composable
fun PageCard(
    imagePath: String,
    modifier: Modifier = Modifier,
    ocrLines: List<OcrLine> = emptyList(),
    signature: Signature? = null,
    /** Manual Brightness/Contrast (DESIGN_SPEC §4.3 "Adjust tool") — applied
     * live via a `ColorFilter`, never baked into the file at [imagePath]. */
    brightness: Float = 0f,
    contrast: Float = 1f,
    cropCorners: List<Offset>? = null,
    onCropCornersChange: ((List<Offset>) -> Unit)? = null,
    placementRect: Rect? = null,
    onPlacementRectChange: ((Rect) -> Unit)? = null,
    placementStrokes: List<com.dulatheo.documentscanner.data.model.SignatureStroke> = emptyList(),
    placementRotation: Float = 0f,
    onPlacementRotationChange: ((Float) -> Unit)? = null,
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
                .onSizeChanged { displaySize = it },
        ) {
            AsyncImage(
                model = imagePath,
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(),
                colorFilter = if (brightness != 0f || contrast != 1f) {
                    ColorFilter.colorMatrix(ColorMatrix(brightnessContrastMatrixValues(brightness, contrast, zeroToOneDomain = true)))
                } else null,
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
                    rotation = signature.rotation,
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
                    rotation = placementRotation,
                    onRotationChange = onPlacementRotationChange,
                )
            }
        }
    }
}
