package com.dulatheo.documentscanner.service

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Hands exported files to the platform's native share surface
 * (`Intent.ACTION_SEND` / `ACTION_SEND_MULTIPLE` + chooser), per
 * DESIGN_SPEC.md §4.6 — deliberately not a custom share sheet, so the user
 * gets every installed app, Save to Files, Print, and Copy for free.
 */
object ShareUtil {

    private fun authority(context: Context) = "${context.packageName}.fileprovider"

    fun shareFiles(context: Context, files: List<File>, mimeType: String) {
        if (files.isEmpty()) return
        val uris = files.map { file ->
            FileProvider.getUriForFile(context, authority(context), file)
        }

        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                putExtra(Intent.EXTRA_STREAM, uris.first())
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            }
        }.apply {
            type = mimeType
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        val chooser = Intent.createChooser(intent, "Share document").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(chooser)
    }
}
