package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.zip.ZipOutputStream

/**
 * Exports a document's recognized text as a Word (.docx) file — a Premium
 * format (DESIGN_SPEC §5/§9 "Office format export"). DOCX is just a ZIP of
 * XML parts, so this is a small hand-rolled writer rather than a
 * dependency, with a page break between pages. A page with no recognized
 * text yet contributes an empty paragraph rather than being skipped, so the
 * page count in the export still matches the document.
 *
 * Page structure — side-by-side columns, lines merged into reflowable
 * paragraphs, alignment/indent/heading-like emphasis — is reconstructed
 * from OCR bounding boxes by [DocxLineLayout] (a port of the iOS logic, so
 * both platforms export alike); ML Kit reports no font weight/style/
 * underline, so those aren't reconstructed. Runs of lines that look like
 * table rows ([DocxTableDetector]) are rendered as a real OOXML table. See
 * DESIGN_SPEC §5/§9.
 */
object DocxExportService {
    suspend fun buildDocx(documentName: String, pages: List<ExportPage>, outFile: File): File {
        val resolvedPages = pages.map { OoxmlUtil.ensureOcrLines(it) }
        ZipOutputStream(FileOutputStream(outFile)).use { zip ->
            zip.writeEntry("[Content_Types].xml", CONTENT_TYPES)
            zip.writeEntry("_rels/.rels", ROOT_RELS)
            zip.writeEntry("docProps/core.xml", coreXml(documentName))
            zip.writeEntry("word/document.xml", documentXml(resolvedPages))
            zip.writeEntry("word/_rels/document.xml.rels", DOCUMENT_RELS)
        }
        return outFile
    }

    private fun documentXml(pages: List<ExportPage>): String {
        val body = StringBuilder()
        pages.forEachIndexed { index, page ->
            body.append(renderPage(page.ocrLines))
            if (index < pages.size - 1) {
                body.append("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
            }
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>$body${sectionPropertiesXml()}</w:body></w:document>"
    }

    /** Renders one page: full-width runs flow as ordinary paragraphs (with
     * detected tables interleaved), and side-by-side columns become a
     * borderless two-cell table so each column keeps its own reading
     * order — see [DocxLineLayout]. */
    internal fun renderPage(lines: List<OcrLine>): String {
        val output = StringBuilder()
        for (segment in DocxLineLayout.segments(lines)) {
            when (segment) {
                is DocxLineLayout.Segment.Flow ->
                    output.append(renderFlow(segment.lines, segment.bounds))
                // Columns were only recognized because both sides read as
                // prose, so table detection is skipped there — a wide word
                // gap in a justified line would otherwise misfire.
                is DocxLineLayout.Segment.Columns -> output.append(
                    renderColumns(
                        left = renderFlow(segment.left, segment.leftBounds, detectTables = false),
                        right = renderFlow(segment.right, segment.rightBounds, detectTables = false),
                    ),
                )
            }
        }
        return if (output.isEmpty()) "<w:p/>" else output.toString()
    }

    /** Interleaves detected tables with paragraphs, in reading order.
     * Always ends with a paragraph (a table cell requires one). */
    private fun renderFlow(
        lines: List<OcrLine>,
        bounds: DocxLineLayout.Bounds,
        detectTables: Boolean = true,
    ): String {
        // Same top-to-bottom order DocxLineLayout uses, so table line
        // ranges index into the same sequence.
        val sorted = lines.sortedBy { it.top }
        val tables = if (detectTables) DocxTableDetector.detect(sorted) else emptyList()

        val output = StringBuilder()
        var cursor = 0
        fun flushParagraphs(end: Int) {
            if (cursor >= end) return
            for (paragraph in DocxLineLayout.paragraphs(sorted.subList(cursor, end), bounds)) {
                output.append(renderParagraph(paragraph))
            }
        }
        for (table in tables) {
            flushParagraphs(table.lineRange.first)
            output.append(renderTable(table.rows)).append("<w:p/>")
            cursor = table.lineRange.last + 1
        }
        flushParagraphs(sorted.size)
        if (!output.endsWith("</w:p>") && !output.endsWith("<w:p/>")) output.append("<w:p/>")
        return output.toString()
    }

    private fun renderParagraph(paragraph: DocxLineLayout.Paragraph): String {
        val before = if (paragraph.spaceBefore) 160 else 0
        val pPr = StringBuilder("<w:spacing w:before=\"$before\" w:after=\"60\"/>")
        if (paragraph.firstLineIndent) pPr.append("<w:ind w:firstLine=\"425\"/>")
        pPr.append("<w:jc w:val=\"${paragraph.alignment}\"/>")
        val bold = if (paragraph.bold) "<w:b/>" else ""
        return "<w:p><w:pPr>$pPr</w:pPr>" +
            "<w:r><w:rPr>$bold<w:sz w:val=\"$BODY_HALF_POINTS\"/><w:szCs w:val=\"$BODY_HALF_POINTS\"/></w:rPr>" +
            "<w:t xml:space=\"preserve\">${OoxmlUtil.xmlEscape(paragraph.text)}</w:t></w:r></w:p>"
    }

    /** Two equal-width, borderless cells side by side, with a gutter between
     * them; the negative indent keeps the outer text edges on the page
     * margins. */
    private fun renderColumns(left: String, right: String): String {
        val width = pageSetup.contentWidth + 2 * COLUMN_PADDING
        val half = width / 2
        fun cell(content: String) =
            "<w:tc><w:tcPr><w:tcW w:w=\"$half\" w:type=\"dxa\"/></w:tcPr>$content</w:tc>"
        return "<w:tbl><w:tblPr><w:tblW w:w=\"$width\" w:type=\"dxa\"/><w:tblInd w:w=\"-$COLUMN_PADDING\" w:type=\"dxa\"/>" +
            "<w:tblBorders><w:top w:val=\"nil\"/><w:left w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:right w:val=\"nil\"/>" +
            "<w:insideH w:val=\"nil\"/><w:insideV w:val=\"nil\"/></w:tblBorders><w:tblLayout w:type=\"fixed\"/>" +
            "<w:tblCellMar><w:left w:w=\"$COLUMN_PADDING\" w:type=\"dxa\"/><w:right w:w=\"$COLUMN_PADDING\" w:type=\"dxa\"/></w:tblCellMar>" +
            "</w:tblPr><w:tblGrid><w:gridCol w:w=\"$half\"/><w:gridCol w:w=\"$half\"/></w:tblGrid>" +
            "<w:tr>${cell(left)}${cell(right)}</w:tr></w:tbl><w:p/>"
    }

    /** Inner padding of each column cell (twips) — twice this is the gutter. */
    private const val COLUMN_PADDING = 170

    /** Body text size in half-points (11pt) — OCR box heights are too
     * noisy to infer real font sizes from. */
    private const val BODY_HALF_POINTS = 22

    private class PageSetup(val width: Int, val height: Int, val margin: Int) {
        val contentWidth: Int get() = width - 2 * margin
    }

    /** Page size/margins in twentieths of a point: US Letter in the US and
     * Canada, A4 everywhere else; 2cm margins. */
    private val pageSetup: PageSetup by lazy {
        val letter = Locale.getDefault().country in setOf("US", "CA")
        if (letter) PageSetup(12240, 15840, 1134) else PageSetup(11906, 16838, 1134)
    }

    private fun sectionPropertiesXml(): String =
        "<w:sectPr><w:pgSz w:w=\"${pageSetup.width}\" w:h=\"${pageSetup.height}\"/>" +
            "<w:pgMar w:top=\"${pageSetup.margin}\" w:right=\"${pageSetup.margin}\" w:bottom=\"${pageSetup.margin}\" " +
            "w:left=\"${pageSetup.margin}\" w:header=\"567\" w:footer=\"567\" w:gutter=\"0\"/></w:sectPr>"

    private fun renderTable(rows: List<List<String>>): String {
        val columnCount = rows.firstOrNull()?.size ?: return ""
        if (columnCount == 0) return ""
        val grid = "<w:gridCol/>".repeat(columnCount)
        val trs = StringBuilder()
        for (row in rows) {
            val tcs = StringBuilder()
            for (cell in row) {
                tcs.append("<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr><w:p><w:r><w:t xml:space=\"preserve\">")
                    .append(OoxmlUtil.xmlEscape(cell))
                    .append("</w:t></w:r></w:p></w:tc>")
            }
            trs.append("<w:tr>").append(tcs).append("</w:tr>")
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>" +
            "<w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "<w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "<w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "<w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "<w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" +
            "</w:tblBorders></w:tblPr><w:tblGrid>$grid</w:tblGrid>$trs</w:tbl>"
    }

    private fun coreXml(title: String) =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">" +
            "<dc:title>${OoxmlUtil.xmlEscape(title)}</dc:title></cp:coreProperties>"

    private const val CONTENT_TYPES =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>" +
            "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>"

    private const val ROOT_RELS =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>" +
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>"

    private const val DOCUMENT_RELS =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>"
}
