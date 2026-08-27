package com.dulatheo.documentscanner

import android.app.Application
import com.dulatheo.documentscanner.data.DocumentRepository
import com.dulatheo.documentscanner.service.PremiumManager
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader

class DocumentScannerApp : Application() {
    lateinit var repository: DocumentRepository
        private set
    lateinit var premiumManager: PremiumManager
        private set

    override fun onCreate() {
        super.onCreate()
        repository = DocumentRepository(this)
        premiumManager = PremiumManager(this)
        // PDFBox-Android needs its font resources loaded from assets before
        // any PDDocument use (PdfPasswordProtector, the PDF password
        // protection Premium feature) — a one-time, app-wide init.
        PDFBoxResourceLoader.init(applicationContext)
    }
}
