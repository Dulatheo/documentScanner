package com.dulatheo.documentscanner

import android.app.Application
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.service.PremiumManager

class DocumentScannerApp : Application() {
    lateinit var repository: DocumentRepository
        private set
    lateinit var premiumManager: PremiumManager
        private set

    override fun onCreate() {
        super.onCreate()
        repository = DocumentRepository(this)
        premiumManager = PremiumManager(this)
    }
}
