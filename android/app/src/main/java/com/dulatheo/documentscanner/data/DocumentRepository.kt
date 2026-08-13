package com.dulatheo.documentscanner.data

import android.content.Context
import com.dulatheo.documentscanner.data.model.CommentEntity
import com.dulatheo.documentscanner.data.model.DocumentEntity
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import com.dulatheo.documentscanner.data.model.OcrLine
import com.dulatheo.documentscanner.data.model.PageEntity
import com.dulatheo.documentscanner.data.model.Signature
import com.dulatheo.documentscanner.service.ImageStorage
import com.dulatheo.documentscanner.util.JsonCodec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

/** A page that has been captured/edited in-memory (Camera → Edit flow) but
 * not yet persisted as part of a saved [DocumentEntity]. */
data class DraftPage(
    val id: String = UUID.randomUUID().toString(),
    val imagePath: String,
    val originalImagePath: String? = null,
    val ocrText: String? = null,
    val ocrLines: List<OcrLine> = emptyList(),
    val signature: Signature? = null,
)

/** Single entry point the UI layer talks to for persistence — wraps Room DAOs
 * and on-disk image storage so ViewModels never touch either directly. */
class DocumentRepository(context: Context) {

    private val db = AppDatabase.get(context)
    private val documentDao = db.documentDao()
    private val pageDao = db.pageDao()
    private val commentDao = db.commentDao()
    val imageStorage = ImageStorage(context)

    fun observeDocuments(): Flow<List<DocumentWithDetails>> = documentDao.observeAll()

    fun observeDocument(id: String): Flow<DocumentWithDetails?> = documentDao.observeById(id)

    suspend fun getDocument(id: String): DocumentWithDetails? =
        withContext(Dispatchers.IO) { documentDao.getById(id) }

    /** Saves a freshly captured/edited set of pages as a brand-new document
     * and returns the new document's id. */
    suspend fun createDocument(name: String? = null, pages: List<DraftPage>): String =
        withContext(Dispatchers.IO) {
            val docId = UUID.randomUUID().toString()
            val resolvedName = name?.takeIf { it.isNotBlank() } ?: defaultName()
            documentDao.insert(DocumentEntity(id = docId, name = resolvedName))
            val entities = pages.mapIndexed { index, draft ->
                PageEntity(
                    id = draft.id,
                    documentId = docId,
                    order = index,
                    imagePath = draft.imagePath,
                    originalImagePath = draft.originalImagePath,
                    ocrText = draft.ocrText,
                    ocrLinesJson = JsonCodec.encodeOcrLines(draft.ocrLines),
                    signatureJson = draft.signature?.let { JsonCodec.encodeSignature(it) },
                )
            }
            pageDao.insertAll(entities)
            docId
        }

    /** Persists edits (crop/highlight/OCR/signature) made to a single page
     * that already belongs to a saved document. */
    suspend fun updatePage(page: PageEntity) = withContext(Dispatchers.IO) {
        pageDao.update(page)
    }

    suspend fun addComment(documentId: String, text: String, pageIndex: Int? = null) =
        withContext(Dispatchers.IO) {
            commentDao.insert(
                CommentEntity(documentId = documentId, text = text, pageIndex = pageIndex)
            )
        }

    suspend fun deleteDocument(document: DocumentEntity) = withContext(Dispatchers.IO) {
        // Clean up page image files on disk before dropping the DB rows
        // (Room's ForeignKey.CASCADE handles the pages/comments rows).
        val pages = pageDao.forDocument(document.id)
        pages.forEach { page ->
            imageStorage.delete(page.imagePath)
            page.originalImagePath?.let { imageStorage.delete(it) }
        }
        documentDao.delete(document)
    }

    suspend fun renameDocument(document: DocumentEntity, newName: String) =
        withContext(Dispatchers.IO) {
            documentDao.update(document.copy(name = newName))
        }

    private fun defaultName(): String {
        val stamp = SimpleDateFormat("d MMM yyyy, HH:mm", Locale.getDefault()).format(java.util.Date())
        return "Scan $stamp"
    }
}
