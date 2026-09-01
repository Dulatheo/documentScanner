import Foundation

/// Exports a document's recognized text as a Word (.docx) file — a Premium
/// format (DESIGN_SPEC §5/§9 "Office format export"). DOCX is just a ZIP of
/// XML parts, so this is a small hand-rolled writer (via `OOXMLZipWriter`)
/// rather than a dependency: one paragraph per OCR'd line, a page break
/// between pages. A page with no recognized text yet contributes an empty
/// paragraph rather than being skipped, so the page count in the export
/// still matches the document.
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
                for line in lines {
                    body += "<w:p><w:r><w:t xml:space=\"preserve\">\(XMLEscape.text(line.text))</w:t></w:r></w:p>"
                }
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
