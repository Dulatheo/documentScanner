package com.dulatheo.documentscanner.service

import android.graphics.Bitmap
import com.dulatheo.documentscanner.data.model.OcrLine
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * On-device text recognition via ML Kit Text Recognition v2
 * (`com.google.mlkit:text-recognition`, Latin script — the module ships v2
 * as its default recognizer as of 16.x). Runs fully offline.
 */
class OcrService {

    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    data class Result(val fullText: String, val lines: List<OcrLine>)

    /** Recognizes text in [bitmap] and returns the full text plus per-line
     * regions normalized to the bitmap's dimensions (0f..1f), suitable for
     * both "Copy text" and the tap-to-highlight tool. */
    suspend fun recognize(bitmap: Bitmap): Result = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        val w = bitmap.width.toFloat().coerceAtLeast(1f)
        val h = bitmap.height.toFloat().coerceAtLeast(1f)

        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                val lines = mutableListOf<OcrLine>()
                for (block in visionText.textBlocks) {
                    for (line in block.lines) {
                        val box = line.boundingBox ?: continue
                        lines += OcrLine(
                            text = line.text,
                            left = box.left / w,
                            top = box.top / h,
                            right = box.right / w,
                            bottom = box.bottom / h,
                        )
                    }
                }
                cont.resume(Result(fullText = visionText.text, lines = lines))
            }
            .addOnFailureListener { e ->
                if (cont.isActive) cont.resumeWithException(e)
            }
    }
}
