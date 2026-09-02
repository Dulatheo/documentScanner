package com.dulatheo.documentscanner.data

import android.content.Context
import com.dulatheo.documentscanner.R
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

/** A page that has been captured/edited in-memory (Camera → Edit flow) but
 * not yet persisted as part of a saved [DocumentEntity]. [id] doubles as
 * the eventual [PageEntity.id] — for a page loaded from an already-saved
 * document (DESIGN_SPEC §4.4 re-edit flow), it's seeded from that page's
 * real id so saving again updates it in place instead of creating a
 * duplicate; see [ScanSessionViewModel.startExistingSession]. */
data class DraftPage(
    val id: String = UUID.randomUUID().toString(),
    val imagePath: String,
    val originalImagePath: String? = null,
    val ocrText: String? = null,
    val ocrLines: List<OcrLine> = emptyList(),
    val signature: Signature? = null,
    /** Manual Brightness/Contrast (DESIGN_SPEC §4.3 "Adjust tool") — see
     * [PageEntity.brightness]/[PageEntity.contrast]. */
    val brightness: Float = 0f,
    val contrast: Float = 1f,
)

/** An in-progress comment (DESIGN_SPEC §4.3 "Comment tool"), buffered in
 * [ScanSessionViewModel] until Save/Export writes it to a real
 * [CommentEntity] — works the same whether the document is brand-new or
 * an existing one being re-edited. [existingCommentId] just tracks which
 * draft already has a persisted counterpart, in case editing an existing
 * comment is ever added later (today there's only add, never edit). */
data class DraftComment(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
    val pageIndex: Int? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val existingCommentId: String? = null,
)

/** Single entry point the UI layer talks to for persistence — wraps Room DAOs
 * and on-disk image storage so ViewModels never touch either directly. */
class DocumentRepository(private val context: Context) {

    private val db = AppDatabase.get(context)
    private val documentDao = db.documentDao()
    private val pageDao = db.pageDao()
    private val commentDao = db.commentDao()
    val imageStorage = ImageStorage(context)

    fun observeDocuments(): Flow<List<DocumentWithDetails>> = documentDao.observeAll()

    /** Current size of the saved-documents library — used to gate the
     * free-tier save limit (DESIGN_SPEC §5 "limited document storage"). */
    suspend fun documentCount(): Int = withContext(Dispatchers.IO) { documentDao.observeCount().first() }

    /** Saves a freshly captured/edited set of pages (and any comments
     * added during the session — DESIGN_SPEC §4.3 "Comment tool") as a
     * brand-new document and returns the new document's id. */
    suspend fun createDocument(name: String? = null, pages: List<DraftPage>, comments: List<DraftComment> = emptyList()): String =
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
                    brightness = draft.brightness,
                    contrast = draft.contrast,
                )
            }
            pageDao.insertAll(entities)
            for (comment in comments) {
                commentDao.insert(
                    CommentEntity(documentId = docId, text = comment.text, createdAt = comment.createdAt, pageIndex = comment.pageIndex)
                )
            }
            docId
        }

    /** Updates an already-saved document's pages/comments in place
     * (DESIGN_SPEC §4.4 re-edit flow) rather than creating a new document.
     * [DraftPage.id] doubles as the real [PageEntity.id] (see that type's
     * doc comment), so any page no longer present in [pages] — dropped
     * via the Delete-page tool during this session — is deleted here
     * along with its image files; the rest are upserted. Only comments
     * without an [DraftComment.existingCommentId] are genuinely new;
     * anything loaded in from the document already has its own row. */
    suspend fun updateDocument(documentId: String, pages: List<DraftPage>, comments: List<DraftComment> = emptyList()) =
        withContext(Dispatchers.IO) {
            val previousPages = pageDao.forDocument(documentId)
            val keptIds = pages.map { it.id }.toSet()
            for (page in previousPages) {
                if (page.id !in keptIds) {
                    imageStorage.delete(page.imagePath)
                    page.originalImagePath?.let { imageStorage.delete(it) }
                    pageDao.delete(page)
                }
            }
            val entities = pages.mapIndexed { index, draft ->
                PageEntity(
                    id = draft.id,
                    documentId = documentId,
                    order = index,
                    imagePath = draft.imagePath,
                    originalImagePath = draft.originalImagePath,
                    ocrText = draft.ocrText,
                    ocrLinesJson = JsonCodec.encodeOcrLines(draft.ocrLines),
                    signatureJson = draft.signature?.let { JsonCodec.encodeSignature(it) },
                    brightness = draft.brightness,
                    contrast = draft.contrast,
                )
            }
            pageDao.insertAll(entities)
            for (comment in comments) {
                if (comment.existingCommentId == null) {
                    commentDao.insert(
                        CommentEntity(documentId = documentId, text = comment.text, createdAt = comment.createdAt, pageIndex = comment.pageIndex)
                    )
                }
            }
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
        return context.getString(R.string.default_scan_name_stamped, stamp)
    }
}
