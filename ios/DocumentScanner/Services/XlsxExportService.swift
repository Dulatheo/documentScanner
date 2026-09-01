import Foundation

/// Exports a document's recognized text as an Excel (.xlsx) file — a
/// Premium format (DESIGN_SPEC §5/§9 "Office format export"). One
/// worksheet per page, one row per OCR'd line, all in column A — this app
/// only ever has OCR text (lines + bounding boxes), not detected table
/// structure, so this is honestly "the recognized text, one line per row"
/// rather than a real spreadsheet reconstruction; see DESIGN_SPEC §9 for
/// why real tabular export is a separate, bigger feature.
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
        // Normal editing only runs OCR when the Text/Highlight tool is
        // opened — a page nobody happened to visit either tool on would
        // otherwise export as a sheet with no rows at all.
        let lines = await OCRService.ensureLines(for: page)
        var rows = ""
        for (index, line) in lines.enumerated() {
            let r = index + 1
            rows += "<row r=\"\(r)\"><c r=\"A\(r)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XMLEscape.text(line.text))</t></is></c></row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows)</sheetData></worksheet>
        """
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
