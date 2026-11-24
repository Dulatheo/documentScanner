package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic bilingual two-column page (boxes normalized, top-left origin
 * like ML Kit's [OcrLine]) — the layout that used to export interleaved,
 * one paragraph per scanned line. */
class DocxLineLayoutTest {
    private fun line(text: String, left: Float, top: Float, right: Float) =
        OcrLine(text = text, left = left, top = top, right = right, bottom = top + 0.015f)

    /** One column: two paragraphs of five rows each (indented first row,
     * short last row), with one row split into two side-by-side fragments
     * and one row ending in a hyphenated word. */
    private fun column(prefix: String, minX: Float, maxX: Float): List<OcrLine> {
        val lines = mutableListOf<OcrLine>()
        var y = 0.15f
        for (p in 1..2) {
            for (r in 1..5) {
                val left = if (r == 1) minX + 0.03f else minX
                val right = if (r == 5) minX + (maxX - minX) * 0.5f else maxX
                when {
                    p == 1 && r == 2 -> {
                        val mid = (left + right) / 2f
                        lines += line("$prefix p1 r2a", left, y, mid - 0.02f)
                        lines += line("$prefix p1 r2b", mid + 0.02f, y, right)
                    }
                    p == 2 && r == 3 -> lines += line("$prefix мекен-", left, y, right)
                    else -> lines += line("$prefix p$p r$r", left, y, right)
                }
                y += 0.025f
            }
        }
        return lines
    }

    private val page = listOf(line("ШАРТ / ДОГОВОР", 0.35f, 0.08f, 0.65f)) +
        column("KZ", 0.08f, 0.47f) + column("RU", 0.53f, 0.92f)

    @Test
    fun twoColumnsBecomeOneColumnsSegmentAfterTheTitle() {
        val segments = DocxLineLayout.segments(page)
        assertEquals(2, segments.size)
        assertTrue(segments[0] is DocxLineLayout.Segment.Flow)
        val columns = segments[1] as DocxLineLayout.Segment.Columns
        assertTrue(columns.left.all { it.text.startsWith("KZ") })
        assertTrue(columns.right.all { it.text.startsWith("RU") })
    }

    @Test
    fun columnRowsMergeIntoJustifiedParagraphs() {
        val columns = DocxLineLayout.segments(page)[1] as DocxLineLayout.Segment.Columns
        val paragraphs = DocxLineLayout.paragraphs(columns.left, columns.leftBounds)
        assertEquals(2, paragraphs.size)
        assertEquals("KZ p1 r1 KZ p1 r2a KZ p1 r2b KZ p1 r3 KZ p1 r4 KZ p1 r5", paragraphs[0].text)
        assertEquals("KZ p2 r1 KZ p2 r2 KZ мекен-KZ p2 r4 KZ p2 r5", paragraphs[1].text)
        assertTrue(paragraphs.all { it.alignment == "both" && it.firstLineIndent })
    }

    @Test
    fun renderPageEmitsBorderlessTwoCellTable() {
        val xml = DocxExportService.renderPage(page)
        assertTrue(xml.startsWith("<w:p><w:pPr>"))
        assertTrue(xml.contains("<w:jc w:val=\"center\"/>"))
        assertEquals(1, Regex("<w:tbl>").findAll(xml).count())
        assertEquals(2, Regex("<w:tc>").findAll(xml).count())
        assertTrue(xml.contains("<w:insideV w:val=\"nil\"/>"))
        assertTrue(xml.indexOf("KZ p2 r5") < xml.indexOf("RU p1 r1"))
    }

    @Test
    fun emptyPageIsOneEmptyParagraph() {
        assertEquals("<w:p/>", DocxExportService.renderPage(emptyList()))
    }
}
