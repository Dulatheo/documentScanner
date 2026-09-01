package com.dulatheo.documentscanner.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.Signature

/**
 * Flattens a page's raster image with its committed highlight bands and
 * signature strokes into a single bitmap, for export (PDF/JPG) where the
 * output must be flat pixels. On-screen (Edit/Document viewer) these same
 * elements are instead drawn live as Compose overlays for crisp,
 * interactive rendering — this flattening path exists only for export.
 */
object PageRenderer {

    fun flatten(
        imagePath: String,
        ocrLines: List<OcrLine>,
        signature: Signature?,
        brightness: Float = 0f,
        contrast: Float = 1f,
    ): Bitmap {
        val base = BitmapFactory.decodeFile(imagePath)
            ?: return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        val out = Bitmap.createBitmap(base.width, base.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)

        // Manual Brightness/Contrast (DESIGN_SPEC §4.3 "Adjust tool") — the
        // only element here actually baked into pixels, since (unlike
        // highlights/signature) there's no overlay shape to redraw at
        // export size; drawing `base` onto the blank `out` through a
        // ColorMatrix-filtered Paint achieves the same live-vs-export
        // consistency PageCard's ColorFilter gives on screen. (Drawing
        // `out` onto its own canvas here instead of `base` would read and
        // write the same pixels in one pass — undefined, possibly
        // corrupted output.)
        val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            if (brightness != 0f || contrast != 1f) {
                colorFilter = ColorMatrixColorFilter(ColorMatrix(brightnessContrastMatrixValues(brightness, contrast, zeroToOneDomain = false)))
            }
        }
        canvas.drawBitmap(base, 0f, 0f, basePaint)

        if (ocrLines.any { it.highlighted }) {
            val highlightPaint = Paint().apply {
                color = Color.argb(140, 226, 178, 62) // ~ rgba(226,178,62,.55)
                style = Paint.Style.FILL
            }
            for (line in ocrLines) {
                if (!line.highlighted) continue
                canvas.drawRect(
                    line.left * out.width,
                    line.top * out.height,
                    line.right * out.width,
                    line.bottom * out.height,
                    highlightPaint,
                )
            }
        }

        if (signature != null) {
            drawSignature(canvas, signature, out.width.toFloat(), out.height.toFloat())
        }

        return out
    }

    fun drawSignature(canvas: Canvas, signature: Signature, pageWidthPx: Float, pageHeightPx: Float) {
        val placedWidthPx = signature.width * pageWidthPx
        val placedHeightPx = signature.height * pageHeightPx
        val originX = signature.x * pageWidthPx
        val originY = signature.y * pageHeightPx
        val scaleX = if (signature.canvasWidth > 0) placedWidthPx / signature.canvasWidth else 1f
        val scaleY = if (signature.canvasHeight > 0) placedHeightPx / signature.canvasHeight else 1f

        // Rotate the canvas around the signature's own center to match what
        // was shown on screen (SignaturePlacement's `Modifier.rotate`) —
        // restored right after this signature's strokes are drawn so it
        // doesn't affect anything drawn afterward (highlights are drawn
        // before signatures in `flatten`, but this stays defensive in case
        // that order ever changes).
        val saveCount = canvas.save()
        if (signature.rotation != 0f) {
            canvas.rotate(signature.rotation, originX + placedWidthPx / 2f, originY + placedHeightPx / 2f)
        }
        for (stroke in signature.strokes) {
            if (stroke.points.size < 2) continue
            val paint = Paint().apply {
                color = runCatching { Color.parseColor(stroke.colorHex) }.getOrDefault(Color.BLACK)
                style = Paint.Style.STROKE
                strokeWidth = stroke.widthPx * ((scaleX + scaleY) / 2f)
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
                isAntiAlias = true
            }
            val path = android.graphics.Path()
            stroke.points.forEachIndexed { i, p ->
                val x = originX + p.x * scaleX
                val y = originY + p.y * scaleY
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            canvas.drawPath(path, paint)
        }
        canvas.restoreToCount(saveCount)
    }
}
