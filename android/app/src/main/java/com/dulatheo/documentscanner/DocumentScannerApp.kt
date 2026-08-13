package com.dulatheo.documentscanner

import android.app.Application
import com.dulatheo.documentscanner.data.DocumentRepository

class DocumentScannerApp : Application() {
    lateinit var repository: DocumentRepository
        private set

    override fun onCreate() {
        super.onCreate()
        repository = DocumentRepository(this)
    }
}
