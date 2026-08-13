package com.dulatheo.documentscanner.ui.docviewer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import com.dulatheo.documentscanner.service.ImageStorage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

class DocViewerViewModel(private val repository: DocumentRepository) : ViewModel() {

    val imageStorage: ImageStorage get() = repository.imageStorage

    fun observeDocument(id: String): Flow<DocumentWithDetails?> = repository.observeDocument(id)

    fun addComment(documentId: String, text: String, pageIndex: Int? = null) {
        viewModelScope.launch {
            repository.addComment(documentId, text, pageIndex)
        }
    }

    fun deleteDocument(document: DocumentWithDetails, onDone: () -> Unit) {
        viewModelScope.launch {
            repository.deleteDocument(document.document)
            onDone()
        }
    }
}
