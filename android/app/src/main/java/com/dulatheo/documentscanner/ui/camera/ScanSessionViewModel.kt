package com.dulatheo.documentscanner.ui.camera

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.data.DraftPage

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

    /** Set once [save] succeeds; consumed by the Export sheet's subtitle copy. */
    var savedDocumentId by mutableStateOf<String?>(null)
        private set

    var savedDocumentName by mutableStateOf<String?>(null)
        private set

    fun startSession(newPages: List<DraftPage>) {
        pages = newPages
        currentIndex = 0
        savedDocumentId = null
        savedDocumentName = null
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
     * didn't come out well. Also deletes its on-disk image file(s), since
     * capture/crop already write these to disk immediately (unlike the
     * final save). Clamps [currentIndex] to stay valid, favoring the new
     * last page over resetting to 0 so deleting a page near the end
     * doesn't jump back to the start. */
    fun deletePage(index: Int) {
        if (index !in pages.indices) return
        val removed = pages[index]
        pages = pages.toMutableList().also { it.removeAt(index) }
        imageStorage.delete(removed.imagePath)
        removed.originalImagePath?.let { imageStorage.delete(it) }
        if (pages.isNotEmpty()) {
            currentIndex = currentIndex.coerceAtMost(pages.size - 1)
        }
    }

    suspend fun save(name: String? = null): String {
        val id = repository.createDocument(name = name, pages = pages)
        savedDocumentId = id
        savedDocumentName = name
        return id
    }

    fun clear() {
        pages = emptyList()
        currentIndex = 0
        savedDocumentId = null
        savedDocumentName = null
    }
}
