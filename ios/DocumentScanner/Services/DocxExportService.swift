import Foundation

/// Exports a document's recognized text as a Word (.docx) file — a Premium
/// format (DESIGN_SPEC §5/§9 "Office format export"). DOCX is just a ZIP of
/// XML parts, so this is a small hand-rolled writer (via `OOXMLZipWriter`)
/// rather than a dependency, with a page break between pages. A page with
/// no recognized text yet contributes an empty paragraph rather than being
/// skipped, so the page count in the export still matches the document.
///
/// Page structure — side-by-side columns, lines merged into reflowable
/// paragraphs, alignment/indent/heading-like emphasis — is reconstructed
/// from OCR bounding boxes by `DocxLineLayout`; neither Vision nor ML Kit
/// report font weight/style/underline, so those aren't reconstructed. Runs
/// of lines that look like table rows (`DocxTableDetector`) are rendered
/// as a real OOXML table. See DESIGN_SPEC §5/§9.
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
            body += renderPage(lines)
            if index < pages.count - 1 {
                body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)\(sectionPropertiesXML)</w:body></w:document>
        """
    }

    /// Renders one page: full-width runs flow as ordinary paragraphs (with
    /// detected tables interleaved), and side-by-side columns become a
    /// borderless two-cell table so each column keeps its own reading
    /// order — see `DocxLineLayout`.
    static func renderPage(_ lines: [OCRLine]) -> String {
        var output = ""
        for segment in DocxLineLayout.segments(lines) {
            switch segment {
            case let .flow(flowLines, bounds):
                output += renderFlow(flowLines, in: bounds)
            case let .columns(left, leftBounds, right, rightBounds):
                // Columns were only recognized because both sides read as
                // prose, so table detection is skipped there — a wide word
                // gap in a justified line would otherwise misfire.
                output += renderColumns(
                    left: renderFlow(left, in: leftBounds, detectTables: false),
                    right: renderFlow(right, in: rightBounds, detectTables: false)
                )
            }
        }
        return output.isEmpty ? "<w:p/>" : output
    }

    /// Interleaves detected tables with paragraphs, in reading order.
    /// Always ends with a paragraph (a table cell requires one).
    private static func renderFlow(
        _ lines: [OCRLine],
        in bounds: DocxLineLayout.Bounds,
        detectTables: Bool = true
    ) -> String {
        // Same top-to-bottom order `DocxLineLayout` uses, so table line
        // ranges index into the same sequence.
        let sorted = lines.sorted {
            ($0.normalizedBox.y + $0.normalizedBox.height) > ($1.normalizedBox.y + $1.normalizedBox.height)
        }
        let tables = detectTables ? DocxTableDetector.detect(in: sorted) : []

        var output = ""
        var cursor = 0
        func flushParagraphs(upTo end: Int) {
            guard cursor < end else { return }
            for paragraph in DocxLineLayout.paragraphs(Array(sorted[cursor..<end]), in: bounds) {
                output += renderParagraph(paragraph)
            }
        }
        for table in tables {
            flushParagraphs(upTo: table.lineIndices.lowerBound)
            output += renderTable(table.rows) + "<w:p/>"
            cursor = table.lineIndices.upperBound
        }
        flushParagraphs(upTo: sorted.count)
        if !output.hasSuffix("</w:p>") && !output.hasSuffix("<w:p/>") { output += "<w:p/>" }
        return output
    }

    private static func renderParagraph(_ paragraph: DocxLineLayout.Paragraph) -> String {
        let before = paragraph.spaceBefore ? 160 : 0
        var pPr = "<w:spacing w:before=\"\(before)\" w:after=\"60\"/>"
        if paragraph.firstLineIndent { pPr += "<w:ind w:firstLine=\"425\"/>" }
        pPr += "<w:jc w:val=\"\(paragraph.alignment)\"/>"
        let bold = paragraph.bold ? "<w:b/>" : ""
        return "<w:p><w:pPr>\(pPr)</w:pPr>"
            + "<w:r><w:rPr>\(bold)<w:sz w:val=\"\(bodyHalfPoints)\"/><w:szCs w:val=\"\(bodyHalfPoints)\"/></w:rPr>"
            + "<w:t xml:space=\"preserve\">\(XMLEscape.text(paragraph.text))</w:t></w:r></w:p>"
    }

    /// Two equal-width, borderless cells side by side, with a gutter between
    /// them; the negative indent keeps the outer text edges on the page
    /// margins.
    private static func renderColumns(left: String, right: String) -> String {
        let width = pageSetup.contentWidth + 2 * columnPadding
        let half = width / 2
        let cell = { (content: String) in
            "<w:tc><w:tcPr><w:tcW w:w=\"\(half)\" w:type=\"dxa\"/></w:tcPr>\(content)</w:tc>"
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"\(width)\" w:type=\"dxa\"/><w:tblInd w:w=\"-\(columnPadding)\" w:type=\"dxa\"/>"
            + "<w:tblBorders><w:top w:val=\"nil\"/><w:left w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:right w:val=\"nil\"/>"
            + "<w:insideH w:val=\"nil\"/><w:insideV w:val=\"nil\"/></w:tblBorders><w:tblLayout w:type=\"fixed\"/>"
            + "<w:tblCellMar><w:left w:w=\"\(columnPadding)\" w:type=\"dxa\"/><w:right w:w=\"\(columnPadding)\" w:type=\"dxa\"/></w:tblCellMar>"
            + "</w:tblPr><w:tblGrid><w:gridCol w:w=\"\(half)\"/><w:gridCol w:w=\"\(half)\"/></w:tblGrid>"
            + "<w:tr>\(cell(left))\(cell(right))</w:tr></w:tbl><w:p/>"
    }

    /// Inner padding of each column cell (twips) — twice this is the gutter.
    private static let columnPadding = 170

    /// Body text size in half-points (11pt) — OCR box heights are too
    /// noisy to infer real font sizes from.
    private static let bodyHalfPoints = 22

    /// Page size/margins in twentieths of a point: US Letter in the US and
    /// Canada, A4 everywhere else; 2cm margins.
    private static let pageSetup: (width: Int, height: Int, margin: Int, contentWidth: Int) = {
        let region = Locale.current.region?.identifier ?? ""
        let (width, height) = ["US", "CA"].contains(region) ? (12240, 15840) : (11906, 16838)
        let margin = 1134
        return (width, height, margin, width - 2 * margin)
    }()

    private static var sectionPropertiesXML: String {
        "<w:sectPr><w:pgSz w:w=\"\(pageSetup.width)\" w:h=\"\(pageSetup.height)\"/>"
            + "<w:pgMar w:top=\"\(pageSetup.margin)\" w:right=\"\(pageSetup.margin)\" w:bottom=\"\(pageSetup.margin)\" "
            + "w:left=\"\(pageSetup.margin)\" w:header=\"567\" w:footer=\"567\" w:gutter=\"0\"/></w:sectPr>"
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
