package com.dulatheo.documentscanner.data.model

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * One page of a [DocumentEntity]. Image bytes live on disk under the app's
 * internal storage (see service/ImageStorage.kt); only the file paths are
 * persisted here.
 */
@Entity(
    tableName = "pages",
    foreignKeys = [
        ForeignKey(
            entity = DocumentEntity::class,
            parentColumns = ["id"],
            childColumns = ["documentId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
    indices = [Index("documentId")],
)
data class PageEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val documentId: String,
    val order: Int,
    /** Cropped/edited page image on disk (post auto-crop and any manual re-crop). */
    val imagePath: String,
    /** Pre-crop capture, kept so Crop can be reapplied from the original. */
    val originalImagePath: String? = null,
    /** Full recognized text, null until OCR has been run on this page. */
    val ocrText: String? = null,
    /** Per-line OCR regions (bounding boxes + highlighted flag), JSON-encoded. */
    val ocrLinesJson: String = "[]",
    /** Placed signature, JSON-encoded, null if none. */
    val signatureJson: String? = null,
)
