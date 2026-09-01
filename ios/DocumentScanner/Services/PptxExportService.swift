import UIKit

/// Exports a document as a PowerPoint (.pptx) file — a Premium format
/// (DESIGN_SPEC §5/§9 "Office format export"): one slide per page, each a
/// full-bleed picture of the flattened page (same rendering as JPG export).
/// There's no real "slide content" to extract from a scan beyond the page
/// image itself — see DESIGN_SPEC §9 for why richer slide content is a
/// separate, bigger feature. Slide size is fixed to US Letter proportions
/// (7.5in x 10in) so a full-bleed image doesn't need aspect-fit math.
enum PptxExportService {
    private static let slideWidthEMU = 7_772_400
    private static let slideHeightEMU = 10_058_400

    static func makePptx(for document: DocumentModel) -> URL {
        var zip = OOXMLZipWriter()
        let pages = document.orderedPages
        let count = max(pages.count, 1)

        zip.add(path: "[Content_Types].xml", string: contentTypesXML(slideCount: count))
        zip.add(path: "_rels/.rels", string: rootRelsXML)
        zip.add(path: "ppt/presentation.xml", string: presentationXML(slideCount: count))
        zip.add(path: "ppt/_rels/presentation.xml.rels", string: presentationRelsXML(slideCount: count))
        zip.add(path: "ppt/slideMasters/slideMaster1.xml", string: slideMasterXML)
        zip.add(path: "ppt/slideMasters/_rels/slideMaster1.xml.rels", string: slideMasterRelsXML)
        zip.add(path: "ppt/slideLayouts/slideLayout1.xml", string: slideLayoutXML)
        zip.add(path: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", string: slideLayoutRelsXML)

        for (index, page) in pages.enumerated() {
            let slideNumber = index + 1
            zip.add(path: "ppt/slides/slide\(slideNumber).xml", string: slideXML)
            zip.add(path: "ppt/slides/_rels/slide\(slideNumber).xml.rels", string: slideRelsXML(imageNumber: slideNumber))

            let base = ImageStore.load(page.imagePath) ?? UIImage()
            let flattened = PageRenderer.flatten(base: base, highlightRegions: page.highlightRegions, signature: page.signature)
            let jpegData = flattened.jpegData(compressionQuality: 0.85) ?? Data()
            zip.add(path: "ppt/media/image\(slideNumber).jpeg", data: jpegData)
        }

        let filename = PDFExportService.sanitizedFilename(document.name) + ".pptx"
        return ImageStore.writeExportFile(data: zip.finalize(), filename: filename)
    }

    private static let slideXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:pic><p:nvPicPr><p:cNvPr id="2" name="Page"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(slideWidthEMU)" cy="\(slideHeightEMU)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld></p:sld>
    """

    private static func slideRelsXML(imageNumber: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(imageNumber).jpeg"/></Relationships>
        """
    }

    private static func presentationXML(slideCount: Int) -> String {
        var sldIds = ""
        for i in 0..<slideCount {
            sldIds += "<p:sldId id=\"\(256 + i)\" r:id=\"rId\(i + 2)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(sldIds)</p:sldIdLst><p:sldSz cx="\(slideWidthEMU)" cy="\(slideHeightEMU)"/><p:notesSz cx="\(slideHeightEMU)" cy="\(slideWidthEMU)"/></p:presentation>
        """
    }

    private static func presentationRelsXML(slideCount: Int) -> String {
        var rels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for i in 0..<slideCount {
            rels += "<Relationship Id=\"rId\(i + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i + 1).xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    private static func contentTypesXML(slideCount: Int) -> String {
        var overrides = ""
        for i in 1...slideCount {
            overrides += "<Override PartName=\"/ppt/slides/slide\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>\(overrides)</Types>
        """
    }

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>
    """

    private static let slideMasterXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
    """

    private static let slideMasterRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>
    """

    private static let slideLayoutXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
    """

    private static let slideLayoutRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
    """
}
