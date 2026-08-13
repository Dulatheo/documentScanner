package com.dulatheo.documentscanner.util

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PointF
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Perspective-corrected crop, used by the Edit screen's Crop tool to refine
 * ML Kit's initial auto-crop (DESIGN_SPEC.md §4.3). `android.graphics.Matrix`
 * is a full 3x3 matrix (it has explicit perspective components), and
 * [Matrix.setPolyToPoly] with 4 point pairs solves for the homography that
 * maps the dragged quad onto an axis-aligned rectangle — this is a real
 * projective transform, not just an affine approximation.
 */
object PerspectiveCrop {

    /**
     * Warps the quad [corners] (in `source`'s pixel space, ordered
     * top-left, top-right, bottom-right, bottom-left) onto a rectangle and
     * returns the corrected bitmap. Output size is derived from the quad's
     * own edge lengths when not supplied.
     */
    fun crop(
        source: Bitmap,
        corners: List<PointF>,
        outputWidth: Int? = null,
        outputHeight: Int? = null,
    ): Bitmap {
        require(corners.size == 4) { "Crop requires exactly 4 corners" }
        val (tl, tr, br, bl) = corners

        val topWidth = distance(tl, tr)
        val bottomWidth = distance(bl, br)
        val leftHeight = distance(tl, bl)
        val rightHeight = distance(tr, br)

        val outW = outputWidth ?: max(topWidth, bottomWidth).roundToInt().coerceAtLeast(1)
        val outH = outputHeight ?: max(leftHeight, rightHeight).roundToInt().coerceAtLeast(1)

        val src = floatArrayOf(
            tl.x, tl.y,
            tr.x, tr.y,
            br.x, br.y,
            bl.x, bl.y,
        )
        val dst = floatArrayOf(
            0f, 0f,
            outW.toFloat(), 0f,
            outW.toFloat(), outH.toFloat(),
            0f, outH.toFloat(),
        )

        val matrix = Matrix()
        matrix.setPolyToPoly(src, 0, dst, 0, 4)

        val output = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        canvas.drawBitmap(source, matrix, paint)
        return output
    }

    private fun distance(a: PointF, b: PointF): Float = hypot((a.x - b.x), (a.y - b.y))
}
