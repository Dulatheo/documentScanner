package com.dulatheo.documentscanner.service

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
