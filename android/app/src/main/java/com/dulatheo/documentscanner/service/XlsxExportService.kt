package com.dulatheo.documentscanner.service

import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipOutputStream

/**
 * Exports a document's recognized text as an Excel (.xlsx) file — a
 * Premium format (DESIGN_SPEC §5/§9 "Office format export"). One worksheet
 * per page. Runs of lines [DocxTableDetector] recognizes as a grid-like
 * table (e.g. a scanned two-column glossary/translation table) are spread
 * across columns A, B, C… one detected cell per column, same detector
 * DOCX export already uses to render a real `<w:tbl>` — everything else
 * (ordinary paragraph lines) still goes one line per row in column A, since
 * there's no column structure to split it by.
 */
object XlsxExportService {
    suspend fun buildXlsx(pages: List<ExportPage>, outFile: File): File {
        val sheetCount = maxOf(pages.size, 1)
        val resolvedPages = pages.map { OoxmlUtil.ensureOcrLines(it) }
        ZipOutputStream(FileOutputStream(outFile)).use { zip ->
            zip.writeEntry("[Content_Types].xml", contentTypesXml(sheetCount))
            zip.writeEntry("_rels/.rels", ROOT_RELS)
            zip.writeEntry("xl/workbook.xml", workbookXml(sheetCount))
            zip.writeEntry("xl/_rels/workbook.xml.rels", workbookRelsXml(sheetCount))
            resolvedPages.forEachIndexed { index, page ->
                zip.writeEntry("xl/worksheets/sheet${index + 1}.xml", sheetXml(page))
            }
            if (resolvedPages.isEmpty()) {
                zip.writeEntry("xl/worksheets/sheet1.xml", sheetXml(ExportPage(imagePath = "")))
            }
        }
        return outFile
    }

    private fun sheetXml(page: ExportPage): String {
        // Same top-to-bottom sort DocxExportService/DocxLineLayout use —
        // duplicated here (one line) so table detection agrees with the
        // rest of the export pipeline on reading order without either
        // depending on the other's internals.
        val sorted = page.ocrLines.sortedBy { it.top }
        val tables = DocxTableDetector.detect(sorted)

        val rows = StringBuilder()
        var sheetRow = 0
        var lineIndex = 0
        var tableIndex = 0
        while (lineIndex < sorted.size) {
            if (tableIndex < tables.size && tables[tableIndex].lineRange.first == lineIndex) {
                val table = tables[tableIndex]
                for (rowCells in table.rows) {
                    sheetRow += 1
                    rows.append("<row r=\"$sheetRow\">")
                    rowCells.forEachIndexed { column, cellText ->
                        rows.append(cellXml(column, sheetRow, cellText))
                    }
                    rows.append("</row>")
                }
                lineIndex = table.lineRange.last + 1
                tableIndex += 1
            } else {
                sheetRow += 1
                rows.append("<row r=\"$sheetRow\">").append(cellXml(0, sheetRow, sorted[lineIndex].text)).append("</row>")
                lineIndex += 1
            }
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>$rows</sheetData></worksheet>"
    }

    private fun cellXml(column: Int, row: Int, text: String): String {
        val ref = OoxmlUtil.columnLetter(column) + row
        return "<c r=\"$ref\" t=\"inlineStr\"><is><t xml:space=\"preserve\">${OoxmlUtil.xmlEscape(text)}</t></is></c>"
    }

    private fun workbookXml(sheetCount: Int): String {
        val sheets = StringBuilder()
        for (i in 1..sheetCount) {
            sheets.append("<sheet name=\"Page $i\" sheetId=\"$i\" r:id=\"rId$i\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" +
            "<sheets>$sheets</sheets></workbook>"
    }

    private fun workbookRelsXml(sheetCount: Int): String {
        val rels = StringBuilder()
        for (i in 1..sheetCount) {
            rels.append("<Relationship Id=\"rId$i\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$i.xml\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">$rels</Relationships>"
    }

    private fun contentTypesXml(sheetCount: Int): String {
        val overrides = StringBuilder()
        for (i in 1..sheetCount) {
            overrides.append("<Override PartName=\"/xl/worksheets/sheet$i.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>$overrides</Types>"
    }

    private const val ROOT_RELS =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
}
