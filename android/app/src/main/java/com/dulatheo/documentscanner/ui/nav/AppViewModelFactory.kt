package com.dulatheo.documentscanner.ui.nav

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.service.PremiumManager
import com.dulatheo.documentscanner.ui.camera.ScanSessionViewModel
import com.dulatheo.documentscanner.ui.docviewer.DocViewerViewModel
import com.dulatheo.documentscanner.ui.edit.EditViewModel
import com.dulatheo.documentscanner.ui.home.HomeViewModel

/** Simple hand-rolled factory (no DI framework) wiring the single
 * [DocumentRepository] instance into every screen ViewModel. */
class AppViewModelFactory(
    private val repository: DocumentRepository,
    private val premiumManager: PremiumManager,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T {
        @Suppress("UNCHECKED_CAST")
        return when {
            modelClass.isAssignableFrom(HomeViewModel::class.java) ->
                HomeViewModel(repository) as T
            modelClass.isAssignableFrom(ScanSessionViewModel::class.java) ->
                ScanSessionViewModel(repository) as T
            modelClass.isAssignableFrom(EditViewModel::class.java) ->
                EditViewModel(repository, premiumManager) as T
            modelClass.isAssignableFrom(DocViewerViewModel::class.java) ->
                DocViewerViewModel(repository, premiumManager) as T
            else -> throw IllegalArgumentException("Unknown ViewModel class: $modelClass")
        }
    }
}
