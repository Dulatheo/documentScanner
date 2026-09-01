package com.dulatheo.documentscanner.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.data.model.DocumentWithDetails
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class HomeViewModel(private val repository: DocumentRepository) : ViewModel() {

    private val query = MutableStateFlow("")
    val searchQuery: StateFlow<String> = query

    val documents: StateFlow<List<DocumentWithDetails>> =
        combine(repository.observeDocuments(), query) { docs, q ->
            if (q.isBlank()) docs
            else docs.filter { it.document.name.contains(q, ignoreCase = true) }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun onQueryChange(newQuery: String) {
        query.value = newQuery
    }

    /** Deletes a saved document (DESIGN_SPEC §4.1 "delete a saved
     * document") — image files and the DB rows alike, via
     * [DocumentRepository.deleteDocument]. */
    fun deleteDocument(document: DocumentWithDetails) {
        viewModelScope.launch {
            repository.deleteDocument(document.document)
        }
    }
}
