package com.dulatheo.documentscanner.ui.edit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * Draggable-corner perspective crop overlay (DESIGN_SPEC.md §4.3). [corners]
 * and drag updates are all in the parent Box's local pixel coordinate space
 * (same space as [boxSizePx]); the caller converts to bitmap pixel space at
 * commit time (see [com.dulatheo.documentscanner.util.PerspectiveCrop]).
 */
@Composable
fun CropOverlay(
    corners: List<Offset>,
    onCornersChange: (List<Offset>) -> Unit,
    boxSizePx: IntSize,
    accentColor: Color,
    modifier: Modifier = Modifier,
) {
    val handleRadiusDp = 12.dp
    // detectDragGestures runs for the lifetime of one continuous gesture inside
    // a coroutine that is *not* relaunched on every recomposition (only when
    // the pointerInput key changes) — reading `corners` via rememberUpdatedState
    // (rather than closing over the composable's parameter directly) ensures
    // each drag callback sees the latest value instead of the one captured
    // when the gesture coroutine first started.
    val currentCorners = rememberUpdatedState(corners)
    Box(modifier = modifier) {
        Canvas(modifier = Modifier.matchParentSize()) {
            if (corners.size == 4) {
                val path = Path().apply {
                    moveTo(corners[0].x, corners[0].y)
                    lineTo(corners[1].x, corners[1].y)
                    lineTo(corners[2].x, corners[2].y)
                    lineTo(corners[3].x, corners[3].y)
                    close()
                }
                drawPath(
                    path,
                    color = accentColor,
                    style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round),
                )
            }
        }

        corners.forEachIndexed { index, corner ->
            val clampedX = corner.x.coerceIn(0f, boxSizePx.width.toFloat())
            val clampedY = corner.y.coerceIn(0f, boxSizePx.height.toFloat())
            Box(
                modifier = Modifier
                    .offset {
                        androidx.compose.ui.unit.IntOffset(
                            (clampedX - handleRadiusDp.toPx()).roundToInt(),
                            (clampedY - handleRadiusDp.toPx()).roundToInt(),
                        )
                    }
                    .size(handleRadiusDp * 2)
                    .clip(CircleShape)
                    .pointerInput(index) {
                        detectDragGestures { change, dragAmount ->
                            change.consume()
                            val updated = currentCorners.value.toMutableList()
                            val newX = (updated[index].x + dragAmount.x)
                                .coerceIn(0f, boxSizePx.width.toFloat())
                            val newY = (updated[index].y + dragAmount.y)
                                .coerceIn(0f, boxSizePx.height.toFloat())
                            updated[index] = Offset(newX, newY)
                            onCornersChange(updated)
                        }
                    },
            ) {
                Canvas(modifier = Modifier.matchParentSize()) {
                    drawCircle(color = Color.White, radius = size.minDimension / 2)
                    drawCircle(
                        color = accentColor,
                        radius = size.minDimension / 2,
                        style = Stroke(width = 3.dp.toPx()),
                    )
                }
            }
        }
    }
}
