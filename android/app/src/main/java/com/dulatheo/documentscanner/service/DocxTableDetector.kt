package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.OcrWord
import kotlin.math.abs

/**
 * Detects simple grid-like tables within a page's OCR lines, purely from
 * word-level bounding-box gaps (DESIGN_SPEC §5/§9 "Office format export"
 * table detection) — a table row is usually recognized by ML Kit as one
 * line containing several words, so an unusually large gap between two
 * adjacent words on the same line is treated as a column break.
 * Consecutive lines that split into the same number of cells at matching
 * horizontal positions are grouped into one table; everything else stays
 * a plain paragraph line elsewhere in the export.
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

    /** [sortedLines] must already be in top-to-bottom reading order (see
     * [DocxLineLayout.analyze]'s sort, which callers should apply first). */
    fun detect(sortedLines: List<OcrLine>): List<DetectedTable> {
        if (sortedLines.size < MIN_TABLE_ROWS) return emptyList()

        val allGaps = sortedLines.flatMap { gaps(it) }
        val medianGap = if (allGaps.isEmpty()) 0f else allGaps.sorted()[allGaps.size / 2]
        val threshold = maxOf(medianGap * GAP_FACTOR, MIN_GAP_WIDTH)

        val cellsPerLine = sortedLines.map { cells(it, threshold) }

        val tables = mutableListOf<DetectedTable>()
        var index = 0
        while (index < cellsPerLine.size) {
            if (cellsPerLine[index].size < 2) {
                index += 1
                continue
            }
            var end = index + 1
            while (end < cellsPerLine.size &&
                cellsPerLine[end].size == cellsPerLine[index].size &&
                columnsAlign(cellsPerLine[index], cellsPerLine[end])
            ) {
                end += 1
            }
            if (end - index >= MIN_TABLE_ROWS) {
                val rows = cellsPerLine.subList(index, end).map { row -> row.map { it.text } }
                tables += DetectedTable(lineRange = index until end, rows = rows)
            }
            index = end
        }
        return tables
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
