package com.dulatheo.documentscanner.ui.camera

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.data.DraftComment
import com.dulatheo.documentscanner.data.DraftPage
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import com.dulatheo.documentscanner.util.JsonCodec

/**
 * Holds the in-progress multi-page capture between the Camera and Edit
 * destinations (Activity-scoped — see ui/nav/NavGraph.kt). There is only
 * ever one capture session in flight at a time, so a single shared instance
 * is simpler than threading a serialized page list through nav arguments.
 */
class ScanSessionViewModel(private val repository: DocumentRepository) : ViewModel() {

    val imageStorage get() = repository.imageStorage

    var pages by mutableStateOf<List<DraftPage>>(emptyList())
        private set

    var currentIndex by mutableStateOf(0)
        private set

    /** Comments buffered for this session (DESIGN_SPEC §4.3 "Comment
     * tool") — persisted alongside [pages] on Save/Export, whether this
     * is a brand-new document or a re-edit of an existing one. */
    var comments by mutableStateOf<List<DraftComment>>(emptyList())
        private set

    /** Set when this session is re-editing an already-saved document
     * (DESIGN_SPEC §4.4) rather than a fresh capture — [save] updates
     * that document in place instead of creating a new one. */
    var existingDocumentId by mutableStateOf<String?>(null)
        private set

    /** Set once [save] succeeds; consumed by the Export sheet's subtitle copy. */
    var savedDocumentId by mutableStateOf<String?>(null)
        private set

    var savedDocumentName by mutableStateOf<String?>(null)
        private set

    fun startSession(newPages: List<DraftPage>) {
        pages = newPages
        currentIndex = 0
        comments = emptyList()
        existingDocumentId = null
        savedDocumentId = null
        savedDocumentName = null
    }

    /** Reconstructs an editable session from an already-saved document
     * (DESIGN_SPEC §4.4) — tapping a document on Home reopens the exact
     * same Edit flow a fresh capture uses, just seeded from disk instead
     * of the camera, so every tool (Crop/Adjust/Comment/Text/Sign) and
     * Save/Export work identically either way. [DraftPage.id] is seeded
     * from each [com.dulatheo.documentscanner.data.model.PageEntity.id]
     * so [save] can update pages in place; see [DocumentRepository.updateDocument].
     */
    fun startExistingSession(document: DocumentWithDetails) {
        pages = document.orderedPages.map { page ->
            DraftPage(
                id = page.id,
                imagePath = page.imagePath,
                originalImagePath = page.originalImagePath,
                ocrText = page.ocrText,
                ocrLines = JsonCodec.decodeOcrLines(page.ocrLinesJson),
                signature = JsonCodec.decodeSignature(page.signatureJson),
                brightness = page.brightness,
                contrast = page.contrast,
            )
        }
        currentIndex = 0
        comments = document.orderedComments.map { comment ->
            DraftComment(
                text = comment.text,
                pageIndex = comment.pageIndex,
                createdAt = comment.createdAt,
                existingCommentId = comment.id,
            )
        }
        existingDocumentId = document.document.id
        savedDocumentId = null
        savedDocumentName = null
    }

    /** Appends a new comment to the buffered list (DESIGN_SPEC §4.3
     * "Comment tool") — persisted alongside the rest of the session on
     * Save/Export, not immediately. */
    fun addDraftComment(text: String, pageIndex: Int?) {
        comments = comments + DraftComment(text = text, pageIndex = pageIndex)
    }

    fun addPages(newPages: List<DraftPage>) {
        pages = pages + newPages
    }

    fun goTo(index: Int) {
        if (pages.isEmpty()) return
        currentIndex = index.coerceIn(0, pages.lastIndex)
    }

    fun currentPage(): DraftPage? = pages.getOrNull(currentIndex)

    fun replaceCurrentPage(updater: (DraftPage) -> DraftPage) {
        val idx = currentIndex
        if (idx !in pages.indices) return
        pages = pages.toMutableList().also { it[idx] = updater(it[idx]) }
    }

    /** Removes the page at [index] (DESIGN_SPEC §4.3 "delete a scanned
     * page") — used when reviewing a multi-page capture and one page
     * didn't come out well. For a fresh capture, also deletes its on-disk
     * image file(s) immediately, since capture/crop already write these
     * to disk (unlike the final save) with nothing else referencing them
     * yet. For a re-edit of an existing document ([existingDocumentId]
     * set), the same file is still referenced by that document's
     * persisted row until Save/Export actually runs — deleting it now
     * would leave a dangling reference if the user then cancels instead
     * of saving, so that cleanup is deferred to
     * [DocumentRepository.updateDocument] instead. Clamps [currentIndex]
     * to stay valid, favoring the new last page over resetting to 0 so
     * deleting a page near the end doesn't jump back to the start. */
    fun deletePage(index: Int) {
        if (index !in pages.indices) return
        val removed = pages[index]
        pages = pages.toMutableList().also { it.removeAt(index) }
        if (existingDocumentId == null) {
            imageStorage.delete(removed.imagePath)
            removed.originalImagePath?.let { imageStorage.delete(it) }
        }
        if (pages.isNotEmpty()) {
            currentIndex = currentIndex.coerceAtMost(pages.size - 1)
        }
    }

    suspend fun save(name: String? = null): String {
        val id = existingDocumentId?.also { repository.updateDocument(it, pages, comments) }
            ?: repository.createDocument(name = name, pages = pages, comments = comments)
        savedDocumentId = id
        savedDocumentName = name
        return id
    }

    fun clear() {
        pages = emptyList()
        currentIndex = 0
        comments = emptyList()
        existingDocumentId = null
        savedDocumentId = null
        savedDocumentName = null
    }
}
