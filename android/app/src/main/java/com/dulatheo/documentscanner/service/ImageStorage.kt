package com.dulatheo.documentscanner.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Owns on-disk storage of page images under the app's internal `files/pages`
 * directory. Per DESIGN_SPEC.md §5, the database stores only paths — never
 * image blobs.
 */
class ImageStorage(private val context: Context) {

    private val pagesDir: File by lazy {
        File(context.filesDir, "pages").apply { mkdirs() }
    }

    private val exportsDir: File by lazy {
        File(context.filesDir, "exports").apply { mkdirs() }
    }

    fun exportsDirectory(): File = exportsDir

    /** Copies the content at [sourceUri] (e.g. an ML Kit scanner page result,
     * or a gallery-picked photo) into internal storage and returns the new
     * file's absolute path. */
    fun importFromUri(sourceUri: Uri): String {
        val dest = File(pagesDir, "page_${UUID.randomUUID()}.jpg")
        context.contentResolver.openInputStream(sourceUri).use { input ->
            requireNotNull(input) { "Could not open $sourceUri" }
            FileOutputStream(dest).use { output -> input.copyTo(output) }
        }
        return dest.absolutePath
    }

    /** Persists [bitmap] as a new page image file and returns its absolute path. */
    fun saveBitmap(bitmap: Bitmap, quality: Int = 92): String {
        val dest = File(pagesDir, "page_${UUID.randomUUID()}.jpg")
        FileOutputStream(dest).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        }
        return dest.absolutePath
    }

    /** Overwrites the file at [path] with [bitmap] (used when committing a
     * crop/highlight/signature edit back onto the existing page image). */
    fun overwrite(path: String, bitmap: Bitmap, quality: Int = 92) {
        FileOutputStream(File(path)).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        }
    }

    fun loadBitmap(path: String): Bitmap? = BitmapFactory.decodeFile(path)

    fun duplicate(path: String): String {
        val src = File(path)
        val dest = File(pagesDir, "page_${UUID.randomUUID()}.jpg")
        src.copyTo(dest, overwrite = true)
        return dest.absolutePath
    }

    fun delete(path: String) {
        runCatching { File(path).delete() }
    }

    fun newExportFile(baseName: String, extension: String): File {
        val safeName = baseName.ifBlank { "document" }
            .replace(Regex("[^A-Za-z0-9-_ ]"), "_")
        return File(exportsDir, "$safeName.$extension")
    }
}
