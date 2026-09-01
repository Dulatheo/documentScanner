package com.dulatheo.documentscanner.service

import android.graphics.Bitmap
import com.dulatheo.documentscanner.util.PageRenderer
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipOutputStream

/**
 * Exports a document as a PowerPoint (.pptx) file — a Premium format
 * (DESIGN_SPEC §5/§9 "Office format export"): one slide per page, each a
 * full-bleed picture of the flattened page (same rendering as JPG export).
 * There's no real "slide content" to extract from a scan beyond the page
 * image itself — see DESIGN_SPEC §9 for why richer slide content is a
 * separate, bigger feature. Slide size is fixed to US Letter proportions
 * (7.5in x 10in) so a full-bleed image doesn't need aspect-fit math.
 */
object PptxExportService {
    private const val SLIDE_WIDTH_EMU = 7_772_400
    private const val SLIDE_HEIGHT_EMU = 10_058_400

    fun buildPptx(pages: List<ExportPage>, outFile: File): File {
        val slideCount = maxOf(pages.size, 1)
        ZipOutputStream(FileOutputStream(outFile)).use { zip ->
            zip.writeEntry("[Content_Types].xml", contentTypesXml(slideCount))
            zip.writeEntry("_rels/.rels", ROOT_RELS)
            zip.writeEntry("ppt/presentation.xml", presentationXml(slideCount))
            zip.writeEntry("ppt/_rels/presentation.xml.rels", presentationRelsXml(slideCount))
            zip.writeEntry("ppt/slideMasters/slideMaster1.xml", SLIDE_MASTER_XML)
            zip.writeEntry("ppt/slideMasters/_rels/slideMaster1.xml.rels", SLIDE_MASTER_RELS_XML)
            zip.writeEntry("ppt/slideLayouts/slideLayout1.xml", SLIDE_LAYOUT_XML)
            zip.writeEntry("ppt/slideLayouts/_rels/slideLayout1.xml.rels", SLIDE_LAYOUT_RELS_XML)

            pages.forEachIndexed { index, page ->
                val slideNumber = index + 1
                zip.writeEntry("ppt/slides/slide$slideNumber.xml", SLIDE_XML)
                zip.writeEntry("ppt/slides/_rels/slide$slideNumber.xml.rels", slideRelsXml(slideNumber))

                val flat = PageRenderer.flatten(page.imagePath, page.ocrLines, page.signature, page.brightness, page.contrast)
                val bytes = ByteArrayOutputStream().use { out ->
                    flat.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    out.toByteArray()
                }
                flat.recycle()
                zip.writeEntry("ppt/media/image$slideNumber.jpeg", bytes)
            }
        }
        return outFile
    }

    private val SLIDE_XML =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">" +
            "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>" +
            "<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>" +
            "<p:blipFill><a:blip r:embed=\"rId1\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>" +
            "<p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"$SLIDE_WIDTH_EMU\" cy=\"$SLIDE_HEIGHT_EMU\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>" +
            "</p:spTree></p:cSld></p:sld>"

    private fun slideRelsXml(imageNumber: Int) =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image$imageNumber.jpeg\"/></Relationships>"

    private fun presentationXml(slideCount: Int): String {
        val sldIds = StringBuilder()
        for (i in 0 until slideCount) {
            sldIds.append("<p:sldId id=\"${256 + i}\" r:id=\"rId${i + 2}\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">" +
            "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>" +
            "<p:sldIdLst>$sldIds</p:sldIdLst><p:sldSz cx=\"$SLIDE_WIDTH_EMU\" cy=\"$SLIDE_HEIGHT_EMU\"/>" +
            "<p:notesSz cx=\"$SLIDE_HEIGHT_EMU\" cy=\"$SLIDE_WIDTH_EMU\"/></p:presentation>"
    }

    private fun presentationRelsXml(slideCount: Int): String {
        val rels = StringBuilder(
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        )
        for (i in 0 until slideCount) {
            rels.append("<Relationship Id=\"rId${i + 2}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide${i + 1}.xml\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">$rels</Relationships>"
    }

    private fun contentTypesXml(slideCount: Int): String {
        val overrides = StringBuilder()
        for (i in 1..slideCount) {
            overrides.append("<Override PartName=\"/ppt/slides/slide$i.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>" +
            "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>" +
            "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/>" +
            "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>$overrides</Types>"
    }

    private const val ROOT_RELS =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>"

    private const val SLIDE_MASTER_XML =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<p:sldMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">" +
            "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>" +
            "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>" +
            "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst></p:sldMaster>"

    private const val SLIDE_MASTER_RELS_XML =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/></Relationships>"

    private const val SLIDE_LAYOUT_XML =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<p:sldLayout xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" type=\"blank\" preserve=\"1\">" +
            "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>" +
            "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    private const val SLIDE_LAYOUT_RELS_XML =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>"
}
