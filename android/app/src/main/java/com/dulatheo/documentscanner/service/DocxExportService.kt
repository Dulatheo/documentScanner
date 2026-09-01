package com.dulatheo.documentscanner.service

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
                page.ocrLines.forEach { line ->
                    body.append("<w:p><w:r><w:t xml:space=\"preserve\">")
                        .append(OoxmlUtil.xmlEscape(line.text))
                        .append("</w:t></w:r></w:p>")
                }
            }
            if (index < pages.size - 1) {
                body.append("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
            }
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
            "<w:body>$body<w:sectPr/></w:body></w:document>"
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
