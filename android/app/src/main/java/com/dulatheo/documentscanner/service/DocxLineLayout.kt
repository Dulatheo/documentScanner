package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Approximates paragraph-level layout for DOCX export (DESIGN_SPEC §5/§9
 * "Office format export") from OCR bounding-box geometry alone — ML Kit
 * reports only recognized text plus a position, no font weight/style/
 * underline, so this reconstructs what geometry *can* tell us (alignment,
 * relative emphasis, paragraph breaks) and nothing more: bold/italic/
 * underline detection would need actual pixel-level image analysis
 * (stroke thickness, underline strokes), a separate and riskier
 * "Advanced OCR"-sized feature, not a refinement of this one.
 */
object DocxLineLayout {
    data class Line(
        val text: String,
        /** OOXML `w:jc` value: "left", "center", or "right". */
        val alignment: String,
        /** `w:sz`/`w:szCs` value — font size in half-points. Currently
         * always [BASE_FONT_SIZE_PT]; see that constant's doc comment. */
        val halfPointSize: Int,
        /** Approximated from size alone (see type-level doc) — lines
         * noticeably larger than the page's median line height are
         * treated as emphasized/heading-like, not a real bold detection. */
        val bold: Boolean,
        /** True when the vertical gap before this line is notably larger
         * than the page's typical line-to-line gap, suggesting a
         * paragraph break rather than a mere line wrap. */
        val extraSpaceBefore: Boolean,
    )

    /** Fixed body-text size (11pt, a common Word default) used for every
     * line — scaling this by box-height ratio was tried and looked
     * inconsistent with the actual scan (OCR box heights are too noisy a
     * signal for a size a reader would find plausible), so size is left
     * alone; only alignment/bold/spacing are geometry-derived. */
    private const val BASE_FONT_SIZE_PT = 11f
    private const val BOLD_RATIO_THRESHOLD = 1.4f
    private const val MARGIN_TOLERANCE = 0.02f
    private const val CENTER_TOLERANCE = 0.05f
    private const val CENTERED_MAX_WIDTH_FRACTION = 0.85f
    private const val PARAGRAPH_GAP_FACTOR = 1.6f

    fun analyze(lines: List<OcrLine>): List<Line> {
        if (lines.isEmpty()) return emptyList()

        // OcrLine uses a standard top-left origin (y increases downward),
        // so sorting ascending by `top` is already reading order.
        val sorted = lines.sortedBy { it.top }

        val pageLeftMargin = sorted.minOf { it.left }
        val pageRightEdge = sorted.maxOf { it.right }
        val contentWidth = (pageRightEdge - pageLeftMargin).coerceAtLeast(0.01f)

        val sortedHeights = sorted.map { it.bottom - it.top }.sorted()
        val medianHeight = sortedHeights[sortedHeights.size / 2]

        val gaps = mutableListOf<Float>()
        for (i in 1 until sorted.size) {
            gaps += (sorted[i].top - sorted[i - 1].bottom).coerceAtLeast(0f)
        }
        val medianGap = if (gaps.isEmpty()) 0f else gaps.sorted()[gaps.size / 2]

        return sorted.mapIndexed { index, line ->
            val minX = line.left
            val maxX = line.right
            val midX = (minX + maxX) / 2f
            val lineWidth = line.right - line.left

            val nearLeft = (minX - pageLeftMargin) < MARGIN_TOLERANCE
            val nearRight = (pageRightEdge - maxX) < MARGIN_TOLERANCE
            val centerOffset = abs(midX - 0.5f)

            val alignment = when {
                nearLeft && nearRight -> "left"
                centerOffset < CENTER_TOLERANCE && lineWidth < contentWidth * CENTERED_MAX_WIDTH_FRACTION -> "center"
                nearRight && !nearLeft -> "right"
                else -> "left"
            }

            val ratio = if (medianHeight > 0f) (line.bottom - line.top) / medianHeight else 1f
            val halfPointSize = (BASE_FONT_SIZE_PT * 2).roundToInt()
            val bold = ratio >= BOLD_RATIO_THRESHOLD

            val extraSpaceBefore = if (index > 0) {
                val gap = (line.top - sorted[index - 1].bottom).coerceAtLeast(0f)
                medianGap > 0f && gap > medianGap * PARAGRAPH_GAP_FACTOR
            } else {
                false
            }

            Line(
                text = line.text,
                alignment = alignment,
                halfPointSize = halfPointSize,
                bold = bold,
                extraSpaceBefore = extraSpaceBefore,
            )
        }
    }
}
