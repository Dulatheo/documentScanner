package com.dulatheo.documentscanner.service

import com.dulatheo.documentscanner.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * Test integration with CloudConvert (cloudconvert.com) — a paid cloud
 * conversion API — as an alternative source for DOCX/XLSX/PPTX export
 * (DESIGN_SPEC §5/§9 "Office format export"), tried because the
 * hand-rolled OCR-geometry heuristics in DocxExportService/
 * XlsxExportService/PptxExportService (kept intact and simply unused for
 * now — see ExportManager) produced layout that looked noticeably off
 * from the real scan. This converts the same PDF already generated for
 * plain PDF export (PdfExportService's output, invisible OCR text layer
 * and all) via CloudConvert's own conversion engine, which does real
 * layout reconstruction rather than approximating it from OCR line boxes.
 *
 * Needs `CLOUDCONVERT_API_KEY` in `local.properties` (gitignored, never
 * committed — see local.properties.example). This directly embeds a paid
 * API key in the app, which is fine for local testing but must NOT ship
 * this way: anyone can decompile a release build and extract the key to
 * run up charges on the developer's account. Before shipping, route this
 * through a backend proxy that holds the key server-side instead.
 */
object CloudConvertService {
    private const val BASE_URL = "https://api.cloudconvert.com/v2"
    private const val POLL_INTERVAL_MS = 2000L
    private const val POLL_TIMEOUT_MS = 120_000L

    /** Converts [pdfFile] to [outputFormat] ("docx"/"xlsx"/"pptx") via
     * CloudConvert, writing the result to [outFile]. */
    suspend fun convert(pdfFile: File, outputFormat: String, outFile: File): File =
        withContext(Dispatchers.IO) {
            val apiKey = BuildConfig.CLOUDCONVERT_API_KEY
            check(apiKey.isNotBlank()) {
                "CloudConvert API key not configured — add CLOUDCONVERT_API_KEY to android/local.properties"
            }

            val job = createJob(apiKey, outputFormat)
            val jobId = job.getString("id")
            uploadFile(findTask(job, "import-file"), pdfFile)

            val finishedJob = pollUntilFinished(apiKey, jobId)
            val fileUrl = findTask(finishedJob, "export-file")
                .getJSONObject("result")
                .getJSONArray("files")
                .getJSONObject(0)
                .getString("url")

            downloadFile(fileUrl, outFile)
            outFile
        }

    private fun createJob(apiKey: String, outputFormat: String): JSONObject {
        val body = JSONObject().apply {
            put(
                "tasks",
                JSONObject().apply {
                    put("import-file", JSONObject().put("operation", "import/upload"))
                    put(
                        "convert-file",
                        JSONObject()
                            .put("operation", "convert")
                            .put("input", "import-file")
                            .put("input_format", "pdf")
                            .put("output_format", outputFormat)
                    )
                    put(
                        "export-file",
                        JSONObject()
                            .put("operation", "export/url")
                            .put("input", "convert-file")
                    )
                }
            )
        }
        val connection = openConnection("$BASE_URL/jobs", apiKey, "POST")
        connection.setRequestProperty("Content-Type", "application/json")
        connection.doOutput = true
        connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        return readResponse(connection).getJSONObject("data")
    }

    private fun findTask(job: JSONObject, name: String): JSONObject {
        val tasks = job.getJSONArray("tasks")
        for (i in 0 until tasks.length()) {
            val task = tasks.getJSONObject(i)
            if (task.getString("name") == name) return task
        }
        error("CloudConvert task \"$name\" not found in job response")
    }

    private fun uploadFile(importTask: JSONObject, file: File) {
        val form = importTask.getJSONObject("result").getJSONObject("form")
        val uploadUrl = form.getString("url")
        val parameters = form.getJSONObject("parameters")

        val boundary = "----DocumentScannerBoundary${UUID.randomUUID()}"
        val connection = URL(uploadUrl).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")

        connection.outputStream.use { out ->
            val keys = parameters.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                out.write("--$boundary\r\n".toByteArray())
                out.write("Content-Disposition: form-data; name=\"$key\"\r\n\r\n".toByteArray())
                out.write("${parameters.getString(key)}\r\n".toByteArray())
            }
            out.write("--$boundary\r\n".toByteArray())
            out.write(
                "Content-Disposition: form-data; name=\"file\"; filename=\"${file.name}\"\r\n".toByteArray()
            )
            out.write("Content-Type: application/pdf\r\n\r\n".toByteArray())
            file.inputStream().use { it.copyTo(out) }
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }

        val code = connection.responseCode
        check(code in 200..299) { "CloudConvert upload failed (HTTP $code)" }
        connection.disconnect()
    }

    private suspend fun pollUntilFinished(apiKey: String, jobId: String): JSONObject {
        val deadline = System.currentTimeMillis() + POLL_TIMEOUT_MS
        while (true) {
            val job = readResponse(openConnection("$BASE_URL/jobs/$jobId", apiKey, "GET"))
                .getJSONObject("data")
            when (job.getString("status")) {
                "finished" -> return job
                "error" -> error("CloudConvert job failed: ${job.optString("message", "unknown error")}")
            }
            check(System.currentTimeMillis() < deadline) { "CloudConvert conversion timed out" }
            delay(POLL_INTERVAL_MS)
        }
    }

    private fun downloadFile(url: String, outFile: File) {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connect()
        connection.inputStream.use { input ->
            outFile.outputStream().use { output -> input.copyTo(output) }
        }
        connection.disconnect()
    }

    private fun openConnection(url: String, apiKey: String, method: String): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.setRequestProperty("Authorization", "Bearer $apiKey")
        connection.setRequestProperty("Accept", "application/json")
        return connection
    }

    private fun readResponse(connection: HttpURLConnection): JSONObject {
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val text = stream.bufferedReader().use { it.readText() }
        connection.disconnect()
        check(code in 200..299) { "CloudConvert request failed (HTTP $code): $text" }
        return JSONObject(text)
    }
}
