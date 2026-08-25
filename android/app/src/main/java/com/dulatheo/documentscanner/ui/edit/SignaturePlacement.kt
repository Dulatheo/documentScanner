package com.dulatheo.documentscanner.ui.edit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
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
    val handleRadiusPx = with(density) { 13.dp.toPx() }

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
                        // This box's own bounds fully contain the resize
                        // handle and (partly) the rotate handle drawn below,
                        // so without `isExcluded` this drag would grab their
                        // touches too — Initial fires parent-before-child,
                        // the opposite of the Main pass the handles' own
                        // `detectDragGestures` runs on, so it would win that
                        // race regardless of which one calls `consume()`
                        // first. Excluding their circles lets those touches
                        // fall through to the handles untouched.
                        .priorityDrag(
                            isExcluded = { pos ->
                                val r = currentRect.value
                                isNearHandle(pos, Offset(r.width - handleRadiusPx, r.height - handleRadiusPx), handleRadiusPx) ||
                                    (onRotationChange != null && isNearHandle(pos, Offset(r.width - handleRadiusPx, -handleRadiusPx), handleRadiusPx))
                            },
                        ) { delta ->
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
            // Resize handle, bottom-right corner. Plain `detectDragGestures`
            // (Main pass, child-before-parent) is enough here — it only
            // needs to beat the move box above, which now explicitly steps
            // aside for this handle's region via `isExcluded`.
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

            if (onRotationChange != null) {
                // Rotate handle, top-right corner. Tracks the touch's angle
                // around the box's own center (computed in the box's local,
                // pre-rotation layout frame — Compose's pointer dispatch
                // already accounts for the ancestor `.rotate()` transform
                // when reporting this handle's local touch position, so this
                // math stays correct at any current rotation) and applies
                // only the *change* in angle each frame, so grabbing the
                // handle doesn't snap the signature to point at the finger.
                // Uses the default Main pass, same reasoning as the resize
                // handle above.
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
                                val down = awaitFirstDown()
                                val pointerId = down.id
                                var lastAngle = angleAt(down.position)
                                while (true) {
                                    val event = awaitPointerEvent()
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

private fun isNearHandle(pos: Offset, handleCenter: Offset, radiusPx: Float): Boolean {
    val dx = pos.x - handleCenter.x
    val dy = pos.y - handleCenter.y
    return dx * dx + dy * dy <= radiusPx * radiusPx
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
 *
 * [isExcluded] opts specific down positions (in this modifier's local
 * coordinate space) out of being claimed at all — used so this drag doesn't
 * also steal touches meant for a child handle drawn on top of it, which
 * Initial's parent-before-child ordering would otherwise let it do
 * regardless of the handle's own (Main-pass) consumption.
 */
private fun Modifier.priorityDrag(
    isExcluded: (Offset) -> Boolean = { false },
    onDrag: (Offset) -> Unit,
): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(pass = PointerEventPass.Initial)
        if (isExcluded(down.position)) return@awaitEachGesture
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
