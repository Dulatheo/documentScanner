import Foundation

/// Exports a document's recognized text as a Word (.docx) file — a Premium
/// format (DESIGN_SPEC §5/§9 "Office format export"). DOCX is just a ZIP of
/// XML parts, so this is a small hand-rolled writer (via `OOXMLZipWriter`)
/// rather than a dependency: one paragraph per OCR'd line, a page break
/// between pages. A page with no recognized text yet contributes an empty
/// paragraph rather than being skipped, so the page count in the export
/// still matches the document.
///
/// Alignment/relative size/paragraph spacing are approximated from each
/// line's OCR bounding box (`DocxLineLayout.analyze`) — neither Vision nor
/// ML Kit report font weight/style/underline, only text + position, so
/// bold/italic/underline aren't reconstructed. Runs of lines that look
/// like table rows (`DocxTableDetector`) are rendered as a real OOXML
/// table instead of paragraphs. See DESIGN_SPEC §5/§9.
enum DocxExportService {
    static func makeDocx(for document: DocumentModel) async -> URL {
        var zip = OOXMLZipWriter()

        zip.add(path: "[Content_Types].xml", string: contentTypesXML)
        zip.add(path: "_rels/.rels", string: rootRelsXML)
        zip.add(path: "docProps/core.xml", string: coreXML(title: document.name))
        zip.add(path: "word/document.xml", string: await documentXML(for: document))
        zip.add(path: "word/_rels/document.xml.rels", string: documentRelsXML)

        let filename = PDFExportService.sanitizedFilename(document.name) + ".docx"
        return ImageStore.writeExportFile(data: zip.finalize(), filename: filename)
    }

    private static func documentXML(for document: DocumentModel) async -> String {
        let pages = document.orderedPages
        var body = ""
        for (index, page) in pages.enumerated() {
            // Normal editing only runs OCR when the Text/Highlight tool is
            // opened — a page nobody happened to visit either tool on
            // would otherwise export as a blank paragraph here.
            let lines = await OCRService.ensureLines(for: page)
            if lines.isEmpty {
                body += "<w:p/>"
            } else {
                body += renderPage(lines)
            }
            if index < pages.count - 1 {
                body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr/></w:body></w:document>
        """
    }

    /// Interleaves detected tables with ordinary paragraph lines, in
    /// reading order. Paragraph-layout stats (median height/gap used for
    /// relative bold/spacing) are computed once from only the non-table
    /// lines, so table cell text can't skew what counts as "typical" body
    /// text on the page.
    private static func renderPage(_ lines: [OCRLine]) -> String {
        // Same top-to-bottom sort `DocxLineLayout.analyze` uses internally
        // — duplicated here (one line) so table detection and paragraph
        // rendering agree on line order without either depending on the
        // other's internals.
        let sorted = lines.sorted {
            ($0.normalizedBox.y + $0.normalizedBox.height) > ($1.normalizedBox.y + $1.normalizedBox.height)
        }
        let tables = DocxTableDetector.detect(in: sorted)

        var isTableLine = [Bool](repeating: false, count: sorted.count)
        for table in tables {
            for i in table.lineIndices { isTableLine[i] = true }
        }
        let nonTableLines = zip(sorted, isTableLine).filter { !$0.1 }.map(\.0)
        let analyzedParagraphs = DocxLineLayout.analyze(nonTableLines)

        var output = ""
        var lineIndex = 0
        var paragraphIndex = 0
        var tableIndex = 0
        while lineIndex < sorted.count {
            if tableIndex < tables.count, tables[tableIndex].lineIndices.lowerBound == lineIndex {
                output += renderTable(tables[tableIndex].rows) + "<w:p/>"
                lineIndex = tables[tableIndex].lineIndices.upperBound
                tableIndex += 1
            } else {
                let line = analyzedParagraphs[paragraphIndex]
                paragraphIndex += 1
                if line.extraSpaceBefore {
                    output += "<w:p/>"
                }
                let bold = line.bold ? "<w:b/>" : ""
                output += "<w:p><w:pPr><w:jc w:val=\"\(line.alignment)\"/></w:pPr>"
                output += "<w:r><w:rPr>\(bold)<w:sz w:val=\"\(line.halfPointSize)\"/><w:szCs w:val=\"\(line.halfPointSize)\"/></w:rPr>"
                output += "<w:t xml:space=\"preserve\">\(XMLEscape.text(line.text))</w:t></w:r></w:p>"
                lineIndex += 1
            }
        }
        return output
    }

    private static func renderTable(_ rows: [[String]]) -> String {
        guard let columnCount = rows.first?.count, columnCount > 0 else { return "" }
        var grid = ""
        for _ in 0..<columnCount { grid += "<w:gridCol/>" }
        var trs = ""
        for row in rows {
            var tcs = ""
            for cell in row {
                tcs += "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr><w:p><w:r><w:t xml:space=\"preserve\">\(XMLEscape.text(cell))</w:t></w:r></w:p></w:tc>"
            }
            trs += "<w:tr>\(tcs)</w:tr>"
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>"
            + "<w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "<w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "<w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "<w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "<w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            + "</w:tblBorders></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(trs)</w:tbl>"
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
    """

    private static let documentRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    """

    private static func coreXML(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(XMLEscape.text(title))</dc:title></cp:coreProperties>
        """
    }
}
