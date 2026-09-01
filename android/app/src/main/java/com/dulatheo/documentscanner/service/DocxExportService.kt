package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.data.model.OcrLine
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipOutputStream

/**
 * Exports a document's recognized text as a Word (.docx) file — a Premium
 * format (DESIGN_SPEC §5/§9 "Office format export"). DOCX is just a ZIP of
 * XML parts: one paragraph per OCR'd line, a page break between pages. A
 * page with no recognized text yet contributes an empty paragraph rather
 * than being skipped, so the page count in the export still matches the
 * document.
 *
 * Alignment/relative size/paragraph spacing are approximated from each
 * line's OCR bounding box ([DocxLineLayout.analyze]) — ML Kit reports no
 * font weight/style/underline, only text + position, so bold/italic/
 * underline aren't reconstructed. Runs of lines that look like table rows
 * ([DocxTableDetector]) are rendered as a real OOXML table instead of
 * paragraphs. See DESIGN_SPEC §5/§9.
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
            if (page.ocrLines.isEmpty()) {
                body.append("<w:p/>")
            } else {
                body.append(renderPage(page.ocrLines))
            }
            if (index < pages.size - 1) {
                body.append("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
            }
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>$body<w:sectPr/></w:body></w:document>"
    }

    /** Interleaves detected tables with ordinary paragraph lines, in
     * reading order. Paragraph-layout stats (median height/gap used for
     * relative bold/spacing) are computed once from only the non-table
     * lines, so table cell text can't skew what counts as "typical" body
     * text on the page. */
    private fun renderPage(lines: List<OcrLine>): String {
        // Same top-to-bottom sort DocxLineLayout.analyze uses internally —
        // duplicated here (one line) so table detection and paragraph
        // rendering agree on line order without either depending on the
        // other's internals.
        val sorted = lines.sortedBy { it.top }
        val tables = DocxTableDetector.detect(sorted)

        val isTableLine = BooleanArray(sorted.size)
        for (table in tables) {
            for (i in table.lineRange) isTableLine[i] = true
        }
        val nonTableLines = sorted.filterIndexed { i, _ -> !isTableLine[i] }
        val analyzedParagraphs = DocxLineLayout.analyze(nonTableLines)

        val output = StringBuilder()
        var lineIndex = 0
        var paragraphIndex = 0
        var tableIndex = 0
        while (lineIndex < sorted.size) {
            if (tableIndex < tables.size && tables[tableIndex].lineRange.first == lineIndex) {
                output.append(renderTable(tables[tableIndex].rows)).append("<w:p/>")
                lineIndex = tables[tableIndex].lineRange.last + 1
                tableIndex += 1
            } else {
                val line = analyzedParagraphs[paragraphIndex]
                paragraphIndex += 1
                if (line.extraSpaceBefore) {
                    output.append("<w:p/>")
                }
                val bold = if (line.bold) "<w:b/>" else ""
                output.append("<w:p><w:pPr><w:jc w:val=\"${line.alignment}\"/></w:pPr>")
                    .append("<w:r><w:rPr>$bold<w:sz w:val=\"${line.halfPointSize}\"/><w:szCs w:val=\"${line.halfPointSize}\"/></w:rPr>")
                    .append("<w:t xml:space=\"preserve\">")
                    .append(OoxmlUtil.xmlEscape(line.text))
                    .append("</w:t></w:r></w:p>")
                lineIndex += 1
            }
        }
        return output.toString()
    }

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
