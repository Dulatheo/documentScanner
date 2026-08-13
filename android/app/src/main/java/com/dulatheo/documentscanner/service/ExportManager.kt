package com.dulatheo.documentscanner.service

import android.content.Context
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.util.PageRenderer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

enum class ExportFormat { PDF, JPG }

data class ExportPage(
    val imagePath: String,
    val ocrLines: List<OcrLine> = emptyList(),
    val signature: Signature? = null,
)

/**
 * Builds the export artifact (PDF or per-page JPGs) for a document and hands
 * it to the native share sheet (DESIGN_SPEC.md §4.5-4.6). Committed
 * highlights/signature are flattened onto the raster before export since
 * PDF/JPG output has to be flat pixels (see [PageRenderer]).
 */
class ExportManager(private val context: Context, private val imageStorage: ImageStorage) {

    private val pdfService = PdfExportService()

    suspend fun export(documentName: String, pages: List<ExportPage>, format: ExportFormat): List<File> =
        withContext(Dispatchers.IO) {
            when (format) {
                ExportFormat.PDF -> listOf(exportPdf(documentName, pages))
                ExportFormat.JPG -> exportJpgs(documentName, pages)
            }
        }

    fun shareAndFinish(files: List<File>, format: ExportFormat) {
        val mime = when (format) {
            ExportFormat.PDF -> "application/pdf"
            ExportFormat.JPG -> "image/jpeg"
        }
        ShareUtil.shareFiles(context, files, mime)
    }

    private fun exportPdf(documentName: String, pages: List<ExportPage>): File {
        val flattenedInputs = pages.map { page ->
            val flat = PageRenderer.flatten(page.imagePath, page.ocrLines, page.signature)
            val tempPath = imageStorage.saveBitmap(flat)
            flat.recycle()
            PdfExportService.PageInput(imagePath = tempPath, ocrLines = page.ocrLines)
        }
        val outFile = imageStorage.newExportFile(documentName, "pdf")
        return pdfService.buildPdf(flattenedInputs, outFile)
    }

    private fun exportJpgs(documentName: String, pages: List<ExportPage>): List<File> =
        pages.mapIndexed { index, page ->
            val flat = PageRenderer.flatten(page.imagePath, page.ocrLines, page.signature)
            val suffix = if (pages.size > 1) "_page${index + 1}" else ""
            val outFile = imageStorage.newExportFile("$documentName$suffix", "jpg")
            java.io.FileOutputStream(outFile).use { out ->
                flat.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, out)
            }
            flat.recycle()
            outFile
        }
}
