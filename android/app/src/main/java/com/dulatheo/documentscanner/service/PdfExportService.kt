package com.dulatheo.documentscanner.service

import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import com.dulatheo.documentscanner.data.model.OcrLine
import java.io.File
import java.io.FileOutputStream

/**
 * Builds a multi-page PDF from page images via `android.graphics.pdf.PdfDocument`.
 *
 * Searchable text layer, simplified: `PdfDocument` has no first-class "invisible
 * text layer" API the way PDFKit/PDFKit-on-iOS does (no `PDFTextLayer` /
 * text-annotation concept). To approximate a searchable page, when OCR text
 * is available we draw each recognized line as real text glyphs at its
 * original position with a fully transparent [Paint] (alpha = 0) on top of
 * the page image, sized to match the line's bounding box. Because the text
 * is drawn through the standard Canvas text APIs, the resulting content
 * stream contains real text-showing operators lined up with the image, which
 * most PDF viewers (Google Drive, Adobe Reader, macOS Preview, browsers) will
 * index and let users select/search — but this is a best-effort emulation,
 * not a guaranteed-conformant PDF "invisible text layer"; some strict readers
 * may not expose it as selectable text. See DESIGN_SPEC.md §4.5.
 */
class PdfExportService {

    data class PageInput(
        val imagePath: String,
        val ocrLines: List<OcrLine> = emptyList(),
    )

    fun buildPdf(pages: List<PageInput>, outFile: File): File {
        val document = PdfDocument()
        try {
            pages.forEachIndexed { index, pageInput ->
                val bitmap = BitmapFactory.decodeFile(pageInput.imagePath)
                    ?: return@forEachIndexed
                val pageInfo = PdfDocument.PageInfo.Builder(
                    bitmap.width,
                    bitmap.height,
                    index + 1,
                ).create()
                val page = document.startPage(pageInfo)
                val canvas = page.canvas
                canvas.drawBitmap(bitmap, 0f, 0f, null)

                if (pageInput.ocrLines.isNotEmpty()) {
                    val invisiblePaint = Paint().apply {
                        isAntiAlias = true
                        color = 0x00000000 // fully transparent — alpha 0
                        style = Paint.Style.FILL
                    }
                    for (line in pageInput.ocrLines) {
                        val box = RectF(
                            line.left * bitmap.width,
                            line.top * bitmap.height,
                            line.right * bitmap.width,
                            line.bottom * bitmap.height,
                        )
                        val lineHeightPx = (box.bottom - box.top).coerceAtLeast(1f)
                        invisiblePaint.textSize = lineHeightPx * 0.9f
                        // Shrink/expand horizontally so the glyph run roughly
                        // spans the original line width (keeps search hits'
                        // approximate position sane even though we're not
                        // doing true per-glyph layout).
                        val measured = invisiblePaint.measureText(line.text)
                        val targetWidth = (box.right - box.left).coerceAtLeast(1f)
                        if (measured > 0f) {
                            invisiblePaint.textScaleX = targetWidth / measured
                        }
                        canvas.drawText(line.text, box.left, box.bottom, invisiblePaint)
                        invisiblePaint.textScaleX = 1f
                    }
                }

                document.finishPage(page)
                bitmap.recycle()
            }

            FileOutputStream(outFile).use { out -> document.writeTo(out) }
        } finally {
            document.close()
        }
        return outFile
    }
}
