package com.dulatheo.documentscanner.data.model

import androidx.room.Embedded
import androidx.room.Relation

/** A document together with its ordered pages and comments, as loaded from
 * Room for the home grid / document viewer / edit flow. */
data class DocumentWithDetails(
    @Embedded val document: DocumentEntity,
    @Relation(parentColumn = "id", entityColumn = "documentId")
    val pages: List<PageEntity>,
    @Relation(parentColumn = "id", entityColumn = "documentId")
    val comments: List<CommentEntity>,
) {
    val orderedPages: List<PageEntity> get() = pages.sortedBy { it.order }
    val orderedComments: List<CommentEntity> get() = comments.sortedByDescending { it.createdAt }
}
