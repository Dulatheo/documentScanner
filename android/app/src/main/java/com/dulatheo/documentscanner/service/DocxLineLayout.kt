package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Reconstructs page structure for DOCX export (DESIGN_SPEC §5/§9 "Office
 * format export") from OCR bounding-box geometry alone. Neither ML Kit nor
 * Vision report font weight/style, only recognized text plus a position,
 * so this rebuilds what geometry *can* tell us — a port of the iOS
 * `DocxLineLayout`, kept in step with it so both platforms export alike:
 *
 * 1. **Columns** ([segments]): a vertical gutter that (almost) no line
 *    crosses splits the page into side-by-side columns — e.g. a bilingual
 *    contract with one language per column. Without this, sorting every
 *    line top-to-bottom interleaves the two columns line by line.
 * 2. **Rows**: OCR often splits one justified line into several boxes at
 *    wide word gaps; lines that sit on the same row within a column are
 *    joined back together left to right.
 * 3. **Paragraphs** ([paragraphs]): consecutive rows are merged into one
 *    paragraph unless something signals a break — a first-line indent, a
 *    short previous line, a larger vertical gap, or a list marker — so a
 *    wrapped sentence becomes one Word paragraph that reflows, instead of
 *    one hard paragraph per scanned line.
 *
 * Alignment (left/center/right/justified), a first-line indent and a
 * size-based "heading-like" bold are inferred per paragraph. This is a
 * heuristic on noisy OCR data; it's tuned on real scanned contracts but
 * can misjudge unusual layouts.
 *
 * Coordinates: [OcrLine] boxes are normalized to the page image (0..1) with
 * a top-left origin, so `top` already grows downward in reading order — no
 * flip is needed (unlike Vision's bottom-left boxes on iOS).
 */
object DocxLineLayout {
    data class Paragraph(
        val text: String,
        /** OOXML `w:jc` value: "left", "center", "right" or "both". */
        val alignment: String,
        val firstLineIndent: Boolean,
        /** Approximated from line height alone — not real bold detection. */
        val bold: Boolean,
        /** A larger-than-usual vertical gap preceded this paragraph. */
        val spaceBefore: Boolean,
    )

    /** Horizontal extent (normalized page width) of a region's text — the
     * whole page for full-width flow, or one column. */
    data class Bounds(val minX: Float, val maxX: Float) {
        val width: Float get() = max(maxX - minX, 0.01f)
        val midX: Float get() = (minX + maxX) / 2f
    }

    sealed class Segment {
        /** Full-width content, in reading order. */
        data class Flow(val lines: List<OcrLine>, val bounds: Bounds) : Segment()

        /** Side-by-side columns covering the same vertical stretch. */
        data class Columns(
            val left: List<OcrLine>,
            val leftBounds: Bounds,
            val right: List<OcrLine>,
            val rightBounds: Bounds,
        ) : Segment()
    }

    // region Tuning

    /** The gutter is searched for only within this central band of the page. */
    private const val GUTTER_SEARCH_START = 0.25f
    private const val GUTTER_SEARCH_END = 0.75f
    /** Step between candidate gutter positions. */
    private const val GUTTER_STEP = 0.005f
    /** How far (normalized page width) a line may poke past the gutter
     * before it counts as crossing it — see [findGutter]. */
    private const val GUTTER_SLACK = 0.035f
    /** Each column must hold at least this fraction of the page's lines. */
    private const val MIN_COLUMN_SHARE = 0.2f
    /** A column must look like prose, not a narrow table column: at least
     * this share of its lines span most of the column's width. */
    private const val PROSE_LINE_SHARE = 0.3f
    private const val PROSE_LINE_WIDTH = 0.6f
    /** A row starting this far (fraction of region width) right of the
     * region's left edge counts as indented. */
    private const val INDENT_FRACTION = 0.03f
    /** A row ending this far (fraction of region width) short of the
     * region's right edge counts as a paragraph's last line. */
    private const val SHORT_LINE_FRACTION = 0.12f
    /** A gap must exceed the region's median row gap by this factor to
     * count as a paragraph break. */
    private const val PARAGRAPH_GAP_FACTOR = 1.8f
    /** A paragraph's rows must be this many times the median row height
     * to be treated as heading-like (bold). */
    private const val BOLD_RATIO_THRESHOLD = 1.4f
    /** Vertical half-window (normalized page height) for [localEdges]. */
    private const val LOCAL_WINDOW = 0.08f
    /** Two lines are on the same row once their vertical extents overlap
     * by at least this fraction of the shorter one's height. */
    private const val ROW_OVERLAP_FACTOR = 0.5f

    // endregion

    // region Columns

    fun segments(lines: List<OcrLine>): List<Segment> {
        val sorted = lines.sortedBy { it.top }
        if (sorted.isEmpty()) return emptyList()
        val pageBounds = bounds(sorted)
        val gutter = if (sorted.size >= 6) findGutter(sorted) else null
        if (gutter == null) return listOf(Segment.Flow(sorted, pageBounds))

        val spans = { line: OcrLine -> crosses(line, gutter) }
        val leftBounds = bounds(sorted.filter { !spans(it) && midX(it) < gutter })
        val rightBounds = bounds(sorted.filter { !spans(it) && midX(it) >= gutter })

        val segments = mutableListOf<Segment>()
        var flow = mutableListOf<OcrLine>()
        var left = mutableListOf<OcrLine>()
        var right = mutableListOf<OcrLine>()

        fun flushColumns() {
            if (left.isEmpty() && right.isEmpty()) return
            segments += Segment.Columns(left, leftBounds, right, rightBounds)
            left = mutableListOf()
            right = mutableListOf()
        }
        fun flushFlow() {
            if (flow.isEmpty()) return
            segments += Segment.Flow(flow, pageBounds)
            flow = mutableListOf()
        }

        for (line in sorted) {
            if (spans(line)) {
                flushColumns()
                flow += line
            } else {
                flushFlow()
                if (midX(line) < gutter) left += line else right += line
            }
        }
        flushColumns()
        flushFlow()
        return segments
    }

    private data class Run(val start: Float, val end: Float, val cost: Int) {
        val length: Float get() = end - start
    }

    /**
     * Finds an x position in the middle of the page that (almost) no line
     * crosses, with enough prose-like text on both sides to call it a
     * two-column layout rather than, say, a table or a centered title.
     *
     * A slightly rotated photo makes the columns' edges drift by a percent
     * or so down the page, so neighboring columns can overlap a little in
     * x — a line only counts as crossing a candidate gutter when it
     * extends more than [GUTTER_SLACK] past it on *both* sides.
     */
    private fun findGutter(lines: List<OcrLine>): Float? {
        // A few lines (a title, a signature line) may cross the gutter.
        val tolerance = max(1, (lines.size * 0.06f).toInt())
        val stepCount = ((GUTTER_SEARCH_END - GUTTER_SEARCH_START) / GUTTER_STEP + 0.5f).toInt()
        val crossings = (0..stepCount).map { i ->
            val x = GUTTER_SEARCH_START + i * GUTTER_STEP
            x to lines.count { crosses(it, x) }
        } + (2f to Int.MAX_VALUE) // sentinel closes the last run

        // Longest run of open candidates; ties go to the emptiest run.
        var best: Run? = null
        var run: Run? = null
        for ((x, count) in crossings) {
            if (count <= tolerance) {
                run = run?.let { Run(it.start, x, it.cost + count) } ?: Run(x, x, count)
            } else {
                val current = run ?: continue
                val b = best
                if (b == null ||
                    current.length > b.length + GUTTER_STEP / 2 ||
                    (abs(current.length - b.length) < GUTTER_STEP / 2 && current.cost < b.cost)
                ) {
                    best = current
                }
                run = null
            }
        }
        val found = best ?: return null
        val gutter = (found.start + found.end) / 2f

        val left = lines.filter { !crosses(it, gutter) && midX(it) < gutter }
        val right = lines.filter { !crosses(it, gutter) && midX(it) >= gutter }
        val minLines = max(3, (lines.size * MIN_COLUMN_SHARE).toInt())
        if (left.size < minLines || right.size < minLines ||
            !looksLikeProse(left) || !looksLikeProse(right)
        ) return null
        return gutter
    }

    private fun crosses(line: OcrLine, x: Float): Boolean =
        line.left < x - GUTTER_SLACK && line.right > x + GUTTER_SLACK

    private fun looksLikeProse(lines: List<OcrLine>): Boolean {
        val rows = mergeRows(lines)
        val region = bounds(lines)
        val wide = rows.count { it.maxX - it.minX >= region.width * PROSE_LINE_WIDTH }
        return wide >= rows.size * PROSE_LINE_SHARE
    }

    // endregion

    // region Paragraphs

    /**
     * Merges [lines] (one column, or a full-width run) into paragraphs.
     * [region] is the horizontal extent of the whole column/page the lines
     * belong to, so a short run (a lone title) still judges its alignment
     * against the real page edges rather than its own.
     *
     * Indent/short-line/alignment checks compare each row against its
     * *local* text edges (from nearby rows) rather than the region's
     * overall extent: in a slightly rotated or curved photo the margin
     * drifts down the page, and a page-wide minimum would make every row
     * near the bottom look indented.
     */
    fun paragraphs(lines: List<OcrLine>, region: Bounds): List<Paragraph> {
        val rows = mergeRows(lines)
        if (rows.isEmpty()) return emptyList()
        val edges = rows.map { localEdges(it, rows, region) }

        val heights = rows.map { it.height }.sorted()
        val medianHeight = heights[heights.size / 2]
        val gaps = (1 until rows.size).map { max(rows[it].top - rows[it - 1].bottom, 0f) }
        val medianGap = if (gaps.isEmpty()) 0f else gaps.sorted()[gaps.size / 2]
        val indentThreshold = max(region.width * INDENT_FRACTION, 0.008f)

        fun isIndented(i: Int) = rows[i].minX - edges[i].minX > indentThreshold
        fun isShort(i: Int) = edges[i].maxX - rows[i].maxX > edges[i].width * SHORT_LINE_FRACTION
        fun isBigGap(gap: Float): Boolean =
            if (medianGap > 0f) gap > max(medianGap * PARAGRAPH_GAP_FACTOR, medianHeight * 0.5f)
            else gap > medianHeight * 0.8f

        val groups = mutableListOf<MutableList<Int>>()
        val spaceBefore = mutableListOf<Boolean>()
        for ((i, row) in rows.withIndex()) {
            if (i == 0) {
                groups += mutableListOf(i)
                spaceBefore += false
                continue
            }
            val previous = rows[i - 1]
            val gap = row.top - previous.bottom
            val heightJump = abs(row.height - previous.height) > medianHeight * 0.5f
            val breaks = isIndented(i) || isShort(i - 1) || isBigGap(gap) ||
                startsWithListMarker(row.text) || heightJump
            if (breaks) {
                groups += mutableListOf(i)
                spaceBefore += isBigGap(gap)
            } else {
                groups.last() += i
            }
        }

        return groups.mapIndexed { groupIndex, group ->
            val firstIndex = group[0]
            val first = rows[firstIndex]
            val edge = edges[firstIndex]
            val alignment = if (group.size > 1) {
                "both"
            } else {
                val width = first.maxX - first.minX
                val centerOffset = abs((first.minX + first.maxX) / 2f - edge.midX)
                val leftInset = first.minX - edge.minX
                val rightInset = edge.maxX - first.maxX
                when {
                    centerOffset < edge.width * 0.06f &&
                        width < edge.width * 0.8f &&
                        leftInset > edge.width * 0.08f -> "center"
                    rightInset < edge.width * 0.03f && leftInset > edge.width * 0.3f -> "right"
                    else -> "left"
                }
            }
            val averageHeight = group.map { rows[it].height }.sum() / group.size
            Paragraph(
                text = joinRows(group.map { rows[it].text }),
                alignment = alignment,
                firstLineIndent = alignment != "center" && alignment != "right" && isIndented(firstIndex),
                bold = medianHeight > 0f && averageHeight / medianHeight >= BOLD_RATIO_THRESHOLD,
                spaceBefore = spaceBefore[groupIndex],
            )
        }
    }

    /** The text edges around [row]: the second-outermost left/right edge
     * among rows within [LOCAL_WINDOW] vertically (second, so one stray
     * OCR box poking into the margin doesn't count). Falls back to the
     * whole region when there are too few neighbors to judge. */
    private fun localEdges(row: Row, rows: List<Row>, region: Bounds): Bounds {
        val neighbors = rows.filter { abs(it.top - row.top) <= LOCAL_WINDOW }
        if (neighbors.size < 5) return region
        val lefts = neighbors.map { it.minX }.sorted()
        val rights = neighbors.map { it.maxX }.sortedDescending()
        return Bounds(lefts[1], rights[1])
    }

    private val LIST_MARKER = Regex("""^(\d{1,3}(\.\d{1,3})*[.)]|\p{L}\))\s""")
    private const val BULLET_CHARS = "-–—•·▪●"
    private val STRAY_DIVIDER = Regex("""^[\s,.]*\|\s*""")

    /** "1.", "1.2.", "2)", "а)", "-", "•" … at the start of a row. */
    private fun startsWithListMarker(text: String): Boolean {
        val trimmed = text.trim()
        val first = trimmed.firstOrNull() ?: return false
        if (first in BULLET_CHARS) return true
        return LIST_MARKER.containsMatchIn(trimmed)
    }

    /** Joins wrapped lines with a space, except after a trailing hyphen
     * (a word or compound split across lines — "мекен-" + "жайында"). */
    private fun joinRows(texts: List<String>): String {
        val result = StringBuilder()
        for (raw in texts) {
            // A column divider rule is sometimes read as a stray "|".
            val text = raw.replaceFirst(STRAY_DIVIDER, "").trim()
            if (text.isEmpty()) continue
            when {
                result.isEmpty() -> result.append(text)
                result.endsWith("-") && result.length >= 2 && result[result.length - 2].isLetter() ->
                    result.append(text)
                else -> result.append(' ').append(text)
            }
        }
        return result.toString()
    }

    // endregion

    // region Rows

    private class Row(
        var minX: Float,
        var maxX: Float,
        var top: Float,
        var bottom: Float,
        val parts: MutableList<OcrLine>,
    ) {
        var text: String = ""
        val height: Float get() = bottom - top
    }

    /** Groups lines that sit side by side with substantially overlapping
     * vertical extents into one row, ordered left to right; rows come back
     * top to bottom. */
    private fun mergeRows(lines: List<OcrLine>): List<Row> {
        val rows = mutableListOf<Row>()
        for (line in lines.sortedBy { it.top }) {
            val last = rows.lastOrNull()
            if (last != null) {
                val overlap = min(last.bottom, line.bottom) - max(last.top, line.top)
                val minHeight = min(last.height, line.bottom - line.top)
                // Fragments of one row sit side by side; a line that
                // horizontally overlaps a part already in the row is the
                // next line down, however much their boxes overlap.
                val sideBySide = last.parts.all { part ->
                    min(part.right, line.right) - max(part.left, line.left) < 0.01f
                }
                if (minHeight > 0f && overlap > minHeight * ROW_OVERLAP_FACTOR && sideBySide) {
                    last.parts += line
                    last.minX = min(last.minX, line.left)
                    last.maxX = max(last.maxX, line.right)
                    last.top = min(last.top, line.top)
                    last.bottom = max(last.bottom, line.bottom)
                    continue
                }
            }
            rows += Row(line.left, line.right, line.top, line.bottom, mutableListOf(line))
        }
        for (row in rows) {
            row.text = row.parts.sortedBy { it.left }.joinToString(" ") { it.text }
        }
        return rows
    }

    // endregion

    // region Geometry (top-left origin, normalized)

    private fun midX(line: OcrLine): Float = (line.left + line.right) / 2f

    private fun bounds(lines: List<OcrLine>): Bounds {
        if (lines.isEmpty()) return Bounds(0f, 1f)
        return Bounds(lines.minOf { it.left }, lines.maxOf { it.right })
    }

    // endregion
}
