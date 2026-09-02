package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.OcrWord
import kotlin.math.abs

/**
 * Detects simple grid-like tables within a page's OCR lines, purely from
 * bounding-box geometry (DESIGN_SPEC §5/§9 "Office format export" table
 * detection). A table row reaches OCR as one of two shapes, and both are
 * handled:
 * - **Same `Line`, several words**: cramped columns close enough together
 *   that ML Kit/Vision still grouped them into one line — split by an
 *   unusually large gap between two adjacent *words* on that line.
 * - **Separate `Line`s, same row**: a wide-gapped layout (e.g. a two-column
 *   glossary/translation table) where each column's cell is far enough
 *   from its neighbor that the OCR engine's own line-grouping already
 *   treats them as distinct lines — these are found first by
 *   [rowBands], which groups lines whose vertical extents substantially
 *   overlap (i.e. they sit side by side on the same row) before any
 *   word-gap logic runs. This is in practice the far more common shape for
 *   a real multi-column table, since OCR line-grouping keys off proximity,
 *   and table columns are deliberately spaced apart.
 *
 * Consecutive rows that split into the same number of cells at matching
 * horizontal positions are grouped into one table; everything else stays a
 * plain paragraph line elsewhere in the export.
 *
 * This is a heuristic on noisy OCR data, not real table recognition —
 * there's no ground truth to check it against. It works well on clean,
 * well-spaced tables and can misfire on tight layouts, multi-line cells,
 * or merged cells.
 */
object DocxTableDetector {
    data class DetectedTable(
        /** Indices into the *sorted* (reading-order) line list this table
         * consumed — the caller renders everything outside these ranges
         * as ordinary paragraphs. Exclusive end, like a `List` subrange. */
        val lineRange: IntRange,
        val rows: List<List<String>>,
    )

    private data class Cell(val text: String, val minX: Float)

    /** A group of one or more OCR lines that sit on the same table row —
     * either several separate `Line`s side by side, or (the [lines].size
     * == 1 case) a single line whose own word gaps may still split it into
     * more than one cell. [lineRange] is these lines' contiguous position
     * in the original sorted list. */
    private data class RowBand(val lineRange: IntRange, val lines: List<OcrLine>)

    /** A gap must be at least this many times the page's typical
     * inter-word gap to count as a column break. */
    private const val GAP_FACTOR = 3f

    /** ...and at least this wide outright, in normalized page-width
     * units, so a page with almost no word-spacing data to learn a
     * typical gap from doesn't flag ordinary word spacing. */
    private const val MIN_GAP_WIDTH = 0.02f

    /** How far a cell's left edge may drift between rows and still count
     * as "the same column." */
    private const val COLUMN_ALIGNMENT_TOLERANCE = 0.04f

    /** Minimum rows for a run of same-shaped lines to count as a real
     * table rather than a coincidental one-off multi-column line. */
    private const val MIN_TABLE_ROWS = 2

    /** Two lines count as "the same row" once their vertical extents
     * overlap by at least this fraction of the shorter line's height —
     * side-by-side cells on one row nearly coincide vertically, while
     * lines stacked within a wrapped multi-line cell (or an unrelated line
     * below) don't overlap vertically at all. */
    private const val ROW_OVERLAP_FACTOR = 0.5f

    /** [sortedLines] must already be in top-to-bottom reading order (see
     * [DocxLineLayout.analyze]'s sort, which callers should apply first). */
    fun detect(sortedLines: List<OcrLine>): List<DetectedTable> {
        if (sortedLines.size < MIN_TABLE_ROWS) return emptyList()

        val bands = rowBands(sortedLines)

        // Only used for the same-line word-gap fallback below — computed
        // once, page-wide, same as before.
        val allGaps = sortedLines.flatMap { gaps(it) }
        val medianGap = if (allGaps.isEmpty()) 0f else allGaps.sorted()[allGaps.size / 2]
        val threshold = maxOf(medianGap * GAP_FACTOR, MIN_GAP_WIDTH)

        val cellsPerBand = bands.map { band ->
            if (band.lines.size >= 2) {
                // Already separate lines side by side — each *is* a cell,
                // no word-gap analysis needed.
                band.lines.sortedBy { it.left }.map { Cell(text = it.text, minX = it.left) }
            } else {
                cells(band.lines[0], threshold)
            }
        }

        val tables = mutableListOf<DetectedTable>()
        var index = 0
        while (index < cellsPerBand.size) {
            if (cellsPerBand[index].size < 2) {
                index += 1
                continue
            }
            var end = index + 1
            while (end < cellsPerBand.size &&
                cellsPerBand[end].size == cellsPerBand[index].size &&
                columnsAlign(cellsPerBand[index], cellsPerBand[end])
            ) {
                end += 1
            }
            if (end - index >= MIN_TABLE_ROWS) {
                val rows = cellsPerBand.subList(index, end).map { row -> row.map { it.text } }
                val lineRange = bands[index].lineRange.first until (bands[end - 1].lineRange.last + 1)
                tables += DetectedTable(lineRange = lineRange, rows = rows)
            }
            index = end
        }
        return tables
    }

    /** Greedily groups [sortedLines] into row bands: starting a new band at
     * each line whose vertical extent doesn't sufficiently overlap the
     * current band's combined extent so far. Since the input is already
     * top-to-bottom sorted, lines belonging to the same row are expected to
     * be adjacent, so one linear pass suffices. */
    private fun rowBands(sortedLines: List<OcrLine>): List<RowBand> {
        val bands = mutableListOf<RowBand>()
        var i = 0
        while (i < sortedLines.size) {
            var bandTop = sortedLines[i].top
            var bandBottom = sortedLines[i].bottom
            val bandLines = mutableListOf(sortedLines[i])
            var j = i + 1
            while (j < sortedLines.size) {
                val line = sortedLines[j]
                val overlap = minOf(bandBottom, line.bottom) - maxOf(bandTop, line.top)
                val minHeight = minOf(bandBottom - bandTop, line.bottom - line.top)
                if (minHeight <= 0f || overlap <= minHeight * ROW_OVERLAP_FACTOR) break
                bandLines += line
                bandTop = minOf(bandTop, line.top)
                bandBottom = maxOf(bandBottom, line.bottom)
                j += 1
            }
            bands += RowBand(lineRange = i until j, lines = bandLines)
            i = j
        }
        return bands
    }

    private fun gaps(line: OcrLine): List<Float> {
        if (line.words.size < 2) return emptyList()
        val sorted = line.words.sortedBy { it.left }
        val result = mutableListOf<Float>()
        for (i in 1 until sorted.size) {
            val gap = sorted[i].left - sorted[i - 1].right
            if (gap > 0f) result += gap
        }
        return result
    }

    private fun cells(line: OcrLine, threshold: Float): List<Cell> {
        if (line.words.size < 2) {
            return listOf(Cell(text = line.text, minX = line.left))
        }
        val sorted = line.words.sortedBy { it.left }
        val result = mutableListOf<Cell>()
        var current = mutableListOf(sorted[0])
        for (i in 1 until sorted.size) {
            val gap = sorted[i].left - current.last().right
            if (gap > threshold) {
                result += makeCell(current)
                current = mutableListOf(sorted[i])
            } else {
                current.add(sorted[i])
            }
        }
        result += makeCell(current)
        return result
    }

    private fun makeCell(words: List<OcrWord>): Cell {
        val text = words.joinToString(" ") { it.text }
        val minX = words.minOf { it.left }
        return Cell(text = text, minX = minX)
    }

    private fun columnsAlign(a: List<Cell>, b: List<Cell>): Boolean {
        if (a.size != b.size) return false
        for (i in a.indices) {
            if (abs(a[i].minX - b[i].minX) > COLUMN_ALIGNMENT_TOLERANCE) return false
        }
        return true
    }
}
