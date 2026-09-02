import Foundation

/// Exports a document's recognized text as an Excel (.xlsx) file — a
/// Premium format (DESIGN_SPEC §5/§9 "Office format export"). One
/// worksheet per page. Runs of lines `DocxTableDetector` recognizes as a
/// grid-like table (e.g. a scanned two-column glossary/translation table)
/// are spread across columns A, B, C… one detected cell per column, the
/// same detector DOCX export already uses to render a real Word table;
/// everything else (ordinary paragraph lines) still goes one line per row
/// in column A, since there's no column structure to split it by.
enum XlsxExportService {
    static func makeXlsx(for document: DocumentModel) async -> URL {
        var zip = OOXMLZipWriter()
        let pages = document.orderedPages

        zip.add(path: "[Content_Types].xml", string: contentTypesXML(pageCount: pages.count))
        zip.add(path: "_rels/.rels", string: rootRelsXML)
        zip.add(path: "xl/workbook.xml", string: workbookXML(pageCount: pages.count))
        zip.add(path: "xl/_rels/workbook.xml.rels", string: workbookRelsXML(pageCount: pages.count))
        for (index, page) in pages.enumerated() {
            zip.add(path: "xl/worksheets/sheet\(index + 1).xml", string: await sheetXML(for: page))
        }

        let filename = PDFExportService.sanitizedFilename(document.name) + ".xlsx"
        return ImageStore.writeExportFile(data: zip.finalize(), filename: filename)
    }

    private static func sheetXML(for page: PageModel) async -> String {
        // Normal editing only runs OCR when the Text tool is opened — a
        // page nobody happened to visit it on would otherwise export as a
        // sheet with no rows at all.
        let lines = await OCRService.ensureLines(for: page)
        // Same top-to-bottom sort `DocxExportService.renderPage`/
        // `DocxLineLayout.analyze` use — duplicated here (one line) so
        // table detection agrees with the rest of the export pipeline on
        // reading order without either depending on the other's internals.
        let sorted = lines.sorted {
            ($0.normalizedBox.y + $0.normalizedBox.height) > ($1.normalizedBox.y + $1.normalizedBox.height)
        }
        let tables = DocxTableDetector.detect(in: sorted)

        var rows = ""
        var sheetRow = 0
        var lineIndex = 0
        var tableIndex = 0
        while lineIndex < sorted.count {
            if tableIndex < tables.count, tables[tableIndex].lineIndices.lowerBound == lineIndex {
                let table = tables[tableIndex]
                for rowCells in table.rows {
                    sheetRow += 1
                    rows += "<row r=\"\(sheetRow)\">"
                    for (column, cellText) in rowCells.enumerated() {
                        rows += cellXML(column: column, row: sheetRow, text: cellText)
                    }
                    rows += "</row>"
                }
                lineIndex = table.lineIndices.upperBound
                tableIndex += 1
            } else {
                sheetRow += 1
                rows += "<row r=\"\(sheetRow)\">" + cellXML(column: 0, row: sheetRow, text: sorted[lineIndex].text) + "</row>"
                lineIndex += 1
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows)</sheetData></worksheet>
        """
    }

    private static func cellXML(column: Int, row: Int, text: String) -> String {
        let ref = columnLetter(column) + String(row)
        return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XMLEscape.text(text))</t></is></c>"
    }

    /// Spreadsheet column letter for a 0-based column index (0 -> "A",
    /// 25 -> "Z", 26 -> "AA", …) — the base-26 letter part of an OOXML cell
    /// reference like "B7".
    private static func columnLetter(_ index: Int) -> String {
        var n = index
        var letters: [Character] = []
        repeat {
            let scalarValue = Unicode.Scalar("A").value + UInt32(n % 26)
            letters.insert(Character(Unicode.Scalar(scalarValue)!), at: 0)
            n = n / 26 - 1
        } while n >= 0
        return String(letters)
    }

    private static func workbookXML(pageCount: Int) -> String {
        var sheets = ""
        for i in 1...max(pageCount, 1) {
            sheets += "<sheet name=\"Page \(i)\" sheetId=\"\(i)\" r:id=\"rId\(i)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheets)</sheets></workbook>
        """
    }

    private static func workbookRelsXML(pageCount: Int) -> String {
        var rels = ""
        for i in 1...max(pageCount, 1) {
            rels += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    private static func contentTypesXML(pageCount: Int) -> String {
        var overrides = ""
        for i in 1...max(pageCount, 1) {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\(overrides)</Types>
        """
    }

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """
}
