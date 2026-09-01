package com.dulatheo.documentscanner.service

import android.content.Context
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.util.PageRenderer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

enum class ExportFormat { PDF, JPG, DOCX, XLSX, PPTX }

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

    suspend fun export(
        documentName: String,
        pages: List<ExportPage>,
        format: ExportFormat,
        password: String? = null,
    ): List<File> =
        withContext(Dispatchers.IO) {
            when (format) {
                ExportFormat.PDF -> {
                    val file = exportPdf(documentName, pages)
                    if (!password.isNullOrEmpty()) {
                        PdfPasswordProtector.protect(file, password)
                    }
                    listOf(file)
                }
                ExportFormat.JPG -> exportJpgs(documentName, pages)
                // Routed through CloudConvert (test integration, DESIGN_SPEC
                // §5/§9) rather than the hand-rolled OOXML writers below —
                // those looked noticeably off from the real scan. The
                // hand-rolled path is kept, just unused: swap the three
                // lines below back to
                //   DocxExportService.buildDocx(documentName, pages, imageStorage.newExportFile(documentName, "docx"))
                //   XlsxExportService.buildXlsx(pages, imageStorage.newExportFile(documentName, "xlsx"))
                //   PptxExportService.buildPptx(pages, imageStorage.newExportFile(documentName, "pptx"))
                // to revert.
                ExportFormat.DOCX -> listOf(convertViaCloudConvert(documentName, pages, "docx"))
                ExportFormat.XLSX -> listOf(convertViaCloudConvert(documentName, pages, "xlsx"))
                ExportFormat.PPTX -> listOf(convertViaCloudConvert(documentName, pages, "pptx"))
            }
        }

    /** Generates the same PDF plain PDF export would (invisible OCR text
     * layer and all) and hands it to CloudConvert to convert to
     * [outputFormat] ("docx"/"xlsx"/"pptx") — see [CloudConvertService]. */
    private suspend fun convertViaCloudConvert(
        documentName: String,
        pages: List<ExportPage>,
        outputFormat: String,
    ): File {
        val pdfFile = exportPdf(documentName, pages)
        val outFile = imageStorage.newExportFile(documentName, outputFormat)
        return CloudConvertService.convert(pdfFile, outputFormat, outFile)
    }

    fun shareAndFinish(files: List<File>, format: ExportFormat) {
        val mime = when (format) {
            ExportFormat.PDF -> "application/pdf"
            ExportFormat.JPG -> "image/jpeg"
            ExportFormat.DOCX -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            ExportFormat.XLSX -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            ExportFormat.PPTX -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
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
