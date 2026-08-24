package com.dulatheo.documentscanner.ui.edit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.data.model.SignatureStroke
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.roundToInt

/**
 * Draggable + corner-resizable + rotatable overlay used both while placing a
 * freshly drawn signature and (in read-only form) to render a committed
 * signature. [rect] is in the containing page Box's local, pre-rotation
 * pixel coordinate space; [rotation] (degrees, clockwise) is applied via
 * `Modifier.rotate`, which rotates around this Box's own center — matching
 * iOS's `.rotationEffect` convention for the same field.
 */
@Composable
fun SignaturePlacement(
    strokes: List<SignatureStroke>,
    rect: Rect,
    onRectChange: ((Rect) -> Unit)?,
    accentColor: Color,
    modifier: Modifier = Modifier,
    rotation: Float = 0f,
    onRotationChange: ((Float) -> Unit)? = null,
) {
    val interactive = onRectChange != null
    // The drag/resize/rotate gestures below run for the lifetime of one
    // continuous touch, so keying pointerInput on `rect`/`rotation`
    // themselves (which change every frame while dragging) would restart —
    // and break — the gesture mid-drag. Key on a stable token (`Unit`) and
    // read the latest values via rememberUpdatedState instead.
    val currentRect = rememberUpdatedState(rect)
    val currentRotation = rememberUpdatedState(rotation)
    val density = LocalDensity.current

    Box(
        modifier = modifier
            .offset { IntOffset(rect.left.roundToInt(), rect.top.roundToInt()) }
            .size(
                width = with(density) { rect.width.toDp() },
                height = with(density) { rect.height.toDp() },
            )
            .rotate(rotation)
            .then(
                if (interactive) {
                    Modifier
                        .border(1.dp, accentColor, RoundedCornerShape(4.dp))
                        .background(accentColor.copy(alpha = 0.08f))
                        .priorityDrag { delta ->
                            onRectChange?.invoke(currentRect.value.translate(delta.x, delta.y))
                        }
                } else Modifier
            ),
    ) {
        Canvas(modifier = Modifier.size(
            width = with(density) { rect.width.toDp() },
            height = with(density) { rect.height.toDp() },
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
            // Resize handle, bottom-right corner.
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
                    .priorityDrag { delta ->
                        val base = currentRect.value
                        val newWidth = (base.width + delta.x).coerceAtLeast(40f)
                        val aspect = base.height / base.width
                        val newHeight = (newWidth * aspect).coerceAtLeast(20f)
                        onRectChange?.invoke(
                            Rect(base.left, base.top, base.left + newWidth, base.top + newHeight)
                        )
                    },
            )

            if (onRotationChange != null) {
                // Rotate handle, top-right corner. Tracks the touch's angle
                // around the box's own center (computed in the box's local,
                // pre-rotation layout frame — Compose's pointer dispatch
                // already accounts for the ancestor `.rotate()` transform
                // when reporting this handle's local touch position, so this
                // math stays correct at any current rotation) and applies
                // only the *change* in angle each frame, so grabbing the
                // handle doesn't snap the signature to point at the finger.
                val handleRadiusPx = with(density) { 13.dp.toPx() }
                Box(
                    modifier = Modifier
                        .offset {
                            IntOffset(
                                (rect.width - 13.dp.toPx()).roundToInt(),
                                (-13).dp.roundToPx(),
                            )
                        }
                        .size(26.dp)
                        .clip(CircleShape)
                        .background(accentColor)
                        .pointerInput(Unit) {
                            fun angleAt(localPosInHandle: Offset): Float {
                                val r = currentRect.value
                                val pointInBox = Offset(
                                    r.width - handleRadiusPx + localPosInHandle.x,
                                    -handleRadiusPx + localPosInHandle.y,
                                )
                                val center = Offset(r.width / 2f, r.height / 2f)
                                return atan2(pointInBox.y - center.y, pointInBox.x - center.x)
                            }
                            awaitEachGesture {
                                val down = awaitFirstDown(pass = PointerEventPass.Initial)
                                val pointerId = down.id
                                var lastAngle = angleAt(down.position)
                                while (true) {
                                    val event = awaitPointerEvent(PointerEventPass.Initial)
                                    val change = event.changes.firstOrNull { it.id == pointerId } ?: break
                                    if (change.changedToUpIgnoreConsumed()) break
                                    if (change.positionChange() != Offset.Zero) {
                                        change.consume()
                                        val angle = angleAt(change.position)
                                        var deltaDeg = (angle - lastAngle) * (180f / PI.toFloat())
                                        // Normalize a wraparound jump (crossing the
                                        // ±180° seam) to the short way round, so the
                                        // signature doesn't spin an extra near-full
                                        // turn when the finger crosses it.
                                        if (deltaDeg > 180f) deltaDeg -= 360f
                                        if (deltaDeg < -180f) deltaDeg += 360f
                                        lastAngle = angle
                                        onRotationChange(currentRotation.value + deltaDeg)
                                    }
                                }
                            }
                        },
                )
            }
        }
    }
}

/**
 * A single-pointer drag that consumes position changes during the `Initial`
 * pointer-event pass (root → leaf) rather than the default `Main` pass
 * `detectDragGestures` uses. `EditScreen`'s page content sits inside a
 * `HorizontalPager`, which shares this drag's own horizontal axis — Initial
 * fires, and can consume, before any ancestor's Main-pass handling sees the
 * same event, which is what actually guarantees this drag always wins
 * regardless of the pager's `userScrollEnabled` state, rather than relying
 * on pass-ordering assumptions. The Compose analog of iOS's
 * `.highPriorityGesture` fix for the same "drag axis fights the containing
 * scroll/pager view" class of bug.
 */
private fun Modifier.priorityDrag(onDrag: (Offset) -> Unit): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(pass = PointerEventPass.Initial)
        val pointerId = down.id
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            val change = event.changes.firstOrNull { it.id == pointerId } ?: break
            if (change.changedToUpIgnoreConsumed()) break
            val delta = change.positionChange()
            if (delta != Offset.Zero) {
                change.consume()
                onDrag(delta)
            }
        }
    }
}
