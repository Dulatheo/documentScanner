package com.dulatheo.documentscanner.service

import android.graphics.BitmapFactory
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Shared helpers for the hand-rolled OOXML (DOCX/XLSX/PPTX) writers
 * (DESIGN_SPEC §5/§9 "Office format export") — `java.util.zip.ZipOutputStream`
 * already ships in the JDK, so unlike iOS's `OOXMLZipWriter` this needs no
 * custom ZIP-format code, just XML escaping and a small entry-writing
 * convenience shared across the three writers.
 */
internal object OoxmlUtil {
    private val ocrService by lazy { OcrService() }

    /** Returns [page] with `ocrLines` filled in, running OCR live if it's
     * empty first. Normal editing only runs OCR when the Text/Highlight
     * tool is opened, so a page nobody happened to visit either tool on
     * would otherwise export as empty content in DOCX/XLSX — unlike
     * PDF/JPG, they have no page image to fall back on. */
    suspend fun ensureOcrLines(page: ExportPage): ExportPage {
        if (page.ocrLines.isNotEmpty()) return page
        val bitmap = BitmapFactory.decodeFile(page.imagePath) ?: return page
        val result = ocrService.recognize(bitmap)
        bitmap.recycle()
        return page.copy(ocrLines = result.lines)
    }

    /** Spreadsheet column letter for a 0-based column index (0 -> "A",
     * 25 -> "Z", 26 -> "AA", …) — the base-26 letter part of an OOXML cell
     * reference like "B7". */
    fun columnLetter(index: Int): String {
        var n = index
        val sb = StringBuilder()
        do {
            sb.insert(0, ('A' + n % 26))
            n = n / 26 - 1
        } while (n >= 0)
        return sb.toString()
    }

    fun xmlEscape(s: String): String {
        val sb = StringBuilder(s.length)
        for (c in s) {
            when (c) {
                '&' -> sb.append("&amp;")
                '<' -> sb.append("&lt;")
                '>' -> sb.append("&gt;")
                '"' -> sb.append("&quot;")
                '\'' -> sb.append("&apos;")
                else -> sb.append(c)
            }
        }
        return sb.toString()
    }
}

internal fun ZipOutputStream.writeEntry(name: String, content: String) {
    putNextEntry(ZipEntry(name))
    write(content.toByteArray(Charsets.UTF_8))
    closeEntry()
}

internal fun ZipOutputStream.writeEntry(name: String, content: ByteArray) {
    putNextEntry(ZipEntry(name))
    write(content)
    closeEntry()
}
