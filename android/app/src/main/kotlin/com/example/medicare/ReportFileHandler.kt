package com.example.medicare

import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/** Exports the completed preview PDF without broad storage permissions. */
class ReportFileHandler(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val CREATE_PDF = 35104
        private const val MIME = "application/pdf"
    }

    private data class Pdf(val bytes: ByteArray, val filename: String)
    private data class PickerSave(val pdf: Pdf, val reply: MethodChannel.Result)

    private val channel = MethodChannel(messenger, "medicare/report_files")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    // Accessed only on the main thread, including worker completions.
    private val pending = mutableSetOf<MethodChannel.Result>()
    private var pickerSave: PickerSave? = null
    private var closed = false

    init {
        channel.setMethodCallHandler { call, reply -> handle(call, reply) }
    }

    private fun handle(call: MethodCall, reply: MethodChannel.Result) {
        if (call.method != "savePdf" && call.method != "sharePdf") {
            reply.notImplemented()
            return
        }
        if (closed) {
            reply.error("export_cancelled", "The report screen was closed. Please reopen it.", null)
            return
        }
        val pdf = try {
            val bytes = call.argument<ByteArray>("bytes")
            val filename = call.argument<String>("filename")
            require(bytes != null && bytes.size >= 5 &&
                bytes.copyOfRange(0, 5).contentEquals("%PDF-".toByteArray(Charsets.US_ASCII))) {
                "A valid PDF is required before exporting."
            }
            require(filename != null && filename.endsWith(".pdf", ignoreCase = true) &&
                filename.length > 4 && filename.toByteArray(Charsets.UTF_8).size <= 204 &&
                filename.none { it <= '\u001f' || it == '\u007f' || it in "/\\:*?\"<>|" } &&
                !filename.startsWith('.') && filename.trim() == filename) {
                "The PDF filename is invalid."
            }
            Pdf(bytes.copyOf(), filename)
        } catch (error: Exception) {
            reply.error("invalid_pdf", error.message, null)
            return
        }
        pending.add(reply)
        if (call.method == "sharePdf") {
            share(pdf, reply)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            work(reply) { saveToDownloads(pdf) }
        } else {
            showSavePicker(pdf, reply)
        }
    }

    private fun finish(reply: MethodChannel.Result, complete: () -> Unit) {
        if (pending.remove(reply)) complete()
    }

    private fun fail(reply: MethodChannel.Result, error: Exception) {
        finish(reply) {
            val permission = error is SecurityException
            reply.error(
                if (permission) "permission_denied" else "export_failed",
                if (permission) "Android denied access to the PDF. Choose another location and retry."
                else "Unable to export the PDF. Check available storage and try again.",
                null,
            )
        }
    }

    private fun work(reply: MethodChannel.Result, operation: () -> Any?) {
        io.execute {
            try {
                val result = operation()
                main.post { finish(reply) { reply.success(result) } }
            } catch (error: Exception) {
                main.post { fail(reply, error) }
            }
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private fun saveToDownloads(pdf: Pdf): Map<String, String> {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, pdf.filename)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/MediCare")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Android could not create the download.")
        try {
            writePdf(uri, pdf)
            val name = displayName(uri, pdf.filename)
            val published = resolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            if (published != 1) throw IOException("Android could not publish the download.")
            return mapOf("filename" to name, "uri" to uri.toString(), "location" to "Downloads/MediCare")
        } catch (error: Exception) {
            // Only our newly inserted, incomplete export is removed.
            try { resolver.delete(uri, null, null) } catch (_: Exception) { }
            throw error
        }
    }

    private fun writePdf(uri: Uri, pdf: Pdf) {
        val resolver = activity.contentResolver
        val output = resolver.openOutputStream(uri, "w")
            ?: throw IOException("Android could not open the destination.")
        output.use {
            it.write(pdf.bytes)
            it.flush()
        }
    }

    private fun displayName(uri: Uri, fallback: String): String =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.takeIf(String::isNotBlank) else null
        } ?: fallback

    @Suppress("DEPRECATION")
    private fun showSavePicker(pdf: Pdf, reply: MethodChannel.Result) {
        if (pickerSave != null) {
            finish(reply) { reply.error("export_busy", "Finish the current PDF download first.", null) }
            return
        }
        pickerSave = PickerSave(pdf, reply)
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = MIME
                putExtra(Intent.EXTRA_TITLE, pdf.filename)
            }, CREATE_PDF)
        } catch (error: Exception) {
            pickerSave = null
            fail(reply, error)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_PDF) return false
        val save = pickerSave ?: return true
        pickerSave = null
        if (resultCode != Activity.RESULT_OK) {
            finish(save.reply) { save.reply.success(mapOf("cancelled" to true)) }
            return true
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content") {
            fail(save.reply, IOException("Android did not return a document location."))
            return true
        }
        work(save.reply) {
            try {
                writePdf(uri, save.pdf)
                mapOf("filename" to displayName(uri, save.pdf.filename),
                    "uri" to uri.toString(), "location" to "the selected folder")
            } catch (error: Exception) {
                try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { }
                throw error
            }
        }
        return true
    }

    private fun share(pdf: Pdf, reply: MethodChannel.Result) {
        io.execute {
            var file: File? = null
            try {
                // Keep each immutable share in a separate directory so preparing
                // another report cannot replace an attachment a receiving app is reading.
                val directory = File(activity.cacheDir, "share/${UUID.randomUUID()}")
                if (!directory.mkdirs()) throw IOException("Unable to prepare the PDF attachment.")
                val attachment = File(directory, pdf.filename)
                file = attachment
                attachment.outputStream().use { it.write(pdf.bytes) }
                // Reuse the FileProvider already supplied by the preview's printing plugin.
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.flutter.printing", attachment)
                val clip = ClipData.newUri(activity.contentResolver, pdf.filename, uri)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = MIME
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TITLE, pdf.filename)
                    clipData = clip
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooser = Intent.createChooser(send, "Share medication report").apply {
                    clipData = clip
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                main.post {
                    if (closed || !pending.contains(reply)) {
                        attachment.delete()
                        directory.delete()
                    } else {
                        try {
                            activity.startActivity(chooser)
                            // Do not delete on return: the chosen app may read later.
                            finish(reply) { reply.success(true) }
                        } catch (error: Exception) {
                            attachment.delete()
                            directory.delete()
                            fail(reply, error)
                        }
                    }
                }
            } catch (error: Exception) {
                file?.delete()
                file?.parentFile?.delete()
                main.post { fail(reply, error) }
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        pickerSave = null
        for (reply in pending.toList()) {
            finish(reply) { reply.error("export_cancelled", "The report screen was closed. Please reopen it.", null) }
        }
        // Finish any in-flight write so a lifecycle change cannot leave a partial PDF.
        io.shutdown()
    }
}
