package com.dulatheo.documentscanner.ui.edit

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.data.DraftPage
import com.dulatheo.documentscanner.service.ImageStorage
import com.dulatheo.documentscanner.service.OcrService
import com.dulatheo.documentscanner.service.PremiumManager

/** Backs the per-page editor (Crop / Highlight / Text / Sign). Holds no page
 * state itself — that lives in [com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel]
 * — just the services the tools need and the final "commit to library" call. */
class EditViewModel(
    private val repository: DocumentRepository,
    val premiumManager: PremiumManager,
) : ViewModel() {

    private val ocrService = OcrService()
    val imageStorage: ImageStorage get() = repository.imageStorage

    suspend fun runOcr(bitmap: Bitmap): OcrService.Result = ocrService.recognize(bitmap)

    suspend fun saveDocument(pages: List<DraftPage>, name: String? = null): String =
        repository.createDocument(name = name, pages = pages)

    suspend fun documentCount(): Int = repository.documentCount()
}
