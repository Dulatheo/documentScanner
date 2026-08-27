package com.dulatheo.documentscanner.service

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import java.io.File

/**
 * Encrypts an already-generated PDF with a password (Premium feature —
 * DESIGN_SPEC §5/§9). Deliberately a separate, narrow step rather than a
 * rewrite of [PdfExportService]'s generation pipeline: it loads the plain
 * PDF [PdfExportService] already wrote (PDFBox can load a PDF regardless of
 * what tool created it), applies encryption, and saves it back in place.
 *
 * `com.tom_roush.pdfbox.android.PDFBoxResourceLoader.init(context)` must
 * have been called once before this — PDFBox-Android, unlike desktop
 * PDFBox, needs its font resources loaded from assets first. Called once in
 * [com.dulatheo.documentscanner.DocumentScannerApp.onCreate].
 */
object PdfPasswordProtector {
    /** Same password is used for both the "open" (user) and "permissions"
     * (owner) password — this app has no separate "restrict editing but
     * allow opening" concept to justify two different passwords. 128-bit
     * RC4 is PDFBox-Android's standard encryption strength. */
    fun protect(file: File, password: String) {
        PDDocument.load(file).use { document ->
            val accessPermission = AccessPermission()
            val policy = StandardProtectionPolicy(password, password, accessPermission)
            policy.encryptionKeyLength = 128
            document.protect(policy)
            document.save(file)
        }
    }
}
