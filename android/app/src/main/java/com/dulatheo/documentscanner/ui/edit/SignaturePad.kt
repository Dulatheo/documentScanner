package com.dulatheo.documentscanner.ui.edit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.dulatheo.documentscanner.data.model.SigPoint
import com.dulatheo.documentscanner.data.model.SignatureStroke
import com.dulatheo.documentscanner.ui.theme.LocalAppColors
import kotlin.math.roundToInt

/** The signature drawing pad's fixed internal coordinate space, replayed at
 * any placement size on the page (mirrors the design mock's `sigBox`). */
const val SIGNATURE_CANVAS_WIDTH = 834f
const val SIGNATURE_CANVAS_HEIGHT = 250f

/**
 * Full-screen "Sign with your finger" drawing surface (DESIGN_SPEC.md §4.3):
 * color picker, thickness slider, Clear/Cancel/Done.
 */
@Composable
fun SignaturePad(
    onCancel: () -> Unit,
    onDone: (strokes: List<SignatureStroke>, colorHex: String, thickness: Float) -> Unit,
) {
    val tokens = LocalAppColors.current
    var strokes by remember { mutableStateOf(listOf<SignatureStroke>()) }
    var currentPoints by remember { mutableStateOf(listOf<SigPoint>()) }
    var colorHex by remember { mutableStateOf(SignatureColorOptions[0].second) }
    var thickness by remember { mutableFloatStateOf(5f) }
    // detectDragGestures runs for the lifetime of one continuous gesture inside a
    // coroutine that is only relaunched when the pointerInput key changes. Keying
    // this directly on colorHex/thickness (which can change from the color swatches
    // / thickness slider while a stroke is mid-drag) would restart — and truncate —
    // an in-progress stroke. Key on Unit and read the latest values via
    // rememberUpdatedState instead, matching CropOverlay/SignaturePlacement.
    val currentColorHex = rememberUpdatedState(colorHex)
    val currentThickness = rememberUpdatedState(thickness)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(tokens.bg)
            .padding(horizontal = 20.dp, vertical = 16.dp)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Cancel",
                    color = tokens.ink2,
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.clickable(onClick = onCancel),
                )
                Text("Sign with your finger", color = tokens.ink, style = MaterialTheme.typography.titleSmall)
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(11.dp))
                        .background(tokens.accent)
                        .clickable(enabled = strokes.isNotEmpty()) {
                            onDone(strokes, colorHex, thickness)
                        }
                        .padding(horizontal = 22.dp, vertical = 9.dp),
                ) {
                    Text("Done", color = Color.White, style = MaterialTheme.typography.labelLarge)
                }
            }

            Spacer(Modifier.height(14.dp))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(tokens.paper)
                    .border(1.dp, tokens.line, RoundedCornerShape(10.dp))
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                currentPoints = listOf(SigPoint(offset.x, offset.y))
                            },
                            onDragEnd = {
                                if (currentPoints.size > 1) {
                                    strokes = strokes + SignatureStroke(
                                        currentPoints,
                                        currentColorHex.value,
                                        currentThickness.value,
                                    )
                                }
                                currentPoints = emptyList()
                            },
                            onDrag = { change, _ ->
                                change.consume()
                                currentPoints = currentPoints + SigPoint(change.position.x, change.position.y)
                            },
                        )
                    },
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    // Baseline guide
                    drawLine(
                        color = tokens.paperLine,
                        start = Offset(40f, size.height - 52f),
                        end = Offset(size.width - 40f, size.height - 52f),
                        strokeWidth = 1.dp.toPx(),
                    )
                    val allStrokes = strokes + if (currentPoints.size > 1) {
                        listOf(SignatureStroke(currentPoints, colorHex, thickness))
                    } else emptyList()
                    for (stroke in allStrokes) {
                        if (stroke.points.size < 2) continue
                        val path = Path()
                        stroke.points.forEachIndexed { i, p ->
                            if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
                        }
                        drawPath(
                            path,
                            color = parseHexColor(stroke.colorHex),
                            style = Stroke(
                                width = stroke.widthPx,
                                cap = StrokeCap.Round,
                                join = StrokeJoin.Round,
                            ),
                        )
                    }
                }
                Text(
                    "Sign above the line",
                    color = tokens.ink3,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = 40.dp, bottom = 30.dp),
                )
            }

            Spacer(Modifier.height(12.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)) {
                    SignatureColorOptions.forEach { (name, hex) ->
                        val selected = colorHex == hex
                        Box(
                            modifier = Modifier
                                .size(30.dp)
                                .clip(CircleShape)
                                .background(parseHexColor(hex))
                                .border(
                                    width = 2.dp,
                                    color = if (selected) tokens.accent else tokens.line,
                                    shape = CircleShape,
                                )
                                .clickable { colorHex = hex },
                        )
                    }
                }
                Spacer(Modifier.width(20.dp))
                Text("Thickness", color = tokens.ink3, style = MaterialTheme.typography.labelSmall)
                Spacer(Modifier.width(10.dp))
                androidx.compose.material3.Slider(
                    value = thickness,
                    onValueChange = { thickness = it },
                    valueRange = 2f..12f,
                    modifier = Modifier.weight(1f),
                    colors = androidx.compose.material3.SliderDefaults.colors(
                        thumbColor = tokens.accent,
                        activeTrackColor = tokens.accent,
                        inactiveTrackColor = tokens.line,
                    ),
                )
                Spacer(Modifier.width(12.dp))
                Box(
                    modifier = Modifier
                        .width(34.dp)
                        .height(thickness.roundToInt().coerceAtLeast(2).dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(parseHexColor(colorHex)),
                )
                Spacer(Modifier.width(14.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(11.dp))
                        .border(1.dp, tokens.line, RoundedCornerShape(11.dp))
                        .clickable {
                            strokes = emptyList()
                            currentPoints = emptyList()
                        }
                        .padding(horizontal = 18.dp, vertical = 9.dp),
                ) {
                    Text("Clear", color = tokens.ink2, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

fun parseHexColor(hex: String): Color = runCatching {
    Color(android.graphics.Color.parseColor(hex))
}.getOrDefault(Color.Black)
