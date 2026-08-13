package com.dulatheo.documentscanner.ui.edit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.data.model.SignatureStroke
import kotlin.math.roundToInt

/**
 * Draggable + corner-resizable overlay used both while placing a freshly
 * drawn signature and (in read-only form) to render a committed signature.
 * [rect] is in the containing page Box's local pixel coordinate space.
 */
@Composable
fun SignaturePlacement(
    strokes: List<SignatureStroke>,
    rect: Rect,
    onRectChange: ((Rect) -> Unit)?,
    accentColor: Color,
    modifier: Modifier = Modifier,
) {
    val interactive = onRectChange != null
    // See CropOverlay's comment: detectDragGestures runs for the lifetime of
    // one continuous gesture, so keying pointerInput on `rect` itself (which
    // changes every frame while dragging) would restart — and break — the
    // gesture mid-drag. Key on a stable token and read the latest rect via
    // rememberUpdatedState instead.
    val currentRect = rememberUpdatedState(rect)
    Box(
        modifier = modifier
            .offset { IntOffset(rect.left.roundToInt(), rect.top.roundToInt()) }
            .size(
                width = with(androidx.compose.ui.platform.LocalDensity.current) { rect.width.toDp() },
                height = with(androidx.compose.ui.platform.LocalDensity.current) { rect.height.toDp() },
            )
            .then(
                if (interactive) {
                    Modifier
                        .border(1.dp, accentColor, RoundedCornerShape(4.dp))
                        .background(accentColor.copy(alpha = 0.08f))
                        .pointerInput(Unit) {
                            detectDragGestures { change, dragAmount ->
                                change.consume()
                                onRectChange?.invoke(currentRect.value.translate(dragAmount.x, dragAmount.y))
                            }
                        }
                } else Modifier
            ),
    ) {
        Canvas(modifier = Modifier.size(
            width = with(androidx.compose.ui.platform.LocalDensity.current) { rect.width.toDp() },
            height = with(androidx.compose.ui.platform.LocalDensity.current) { rect.height.toDp() },
        )) {
            val scaleX = size.width / SIGNATURE_CANVAS_WIDTH
            val scaleY = size.height / SIGNATURE_CANVAS_HEIGHT
            for (stroke in strokes) {
                if (stroke.points.size < 2) continue
                val path = Path()
                stroke.points.forEachIndexed { i, p ->
                    val x = p.x * scaleX
                    val y = p.y * scaleY
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(
                    path,
                    color = parseHexColor(stroke.colorHex),
                    style = Stroke(
                        width = stroke.widthPx * ((scaleX + scaleY) / 2f),
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round,
                    ),
                )
            }
        }

        if (interactive) {
            // Resize handle, bottom-right corner
            Box(
                modifier = Modifier
                    .offset {
                        IntOffset(
                            (rect.width - 13.dp.toPx()).roundToInt(),
                            (rect.height - 13.dp.toPx()).roundToInt(),
                        )
                    }
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(accentColor)
                    .pointerInput(Unit) {
                        detectDragGestures { change, dragAmount ->
                            change.consume()
                            val base = currentRect.value
                            val newWidth = (base.width + dragAmount.x).coerceAtLeast(40f)
                            val aspect = base.height / base.width
                            val newHeight = (newWidth * aspect).coerceAtLeast(20f)
                            onRectChange?.invoke(
                                Rect(base.left, base.top, base.left + newWidth, base.top + newHeight)
                            )
                        }
                    },
            )
        }
    }
}
