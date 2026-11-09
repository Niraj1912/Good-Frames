package com.goodframes.app

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Folder mode: instead of sharing every photo, the user picks folders with
// Android's folder picker (the Storage Access Framework). The app can then
// read those folders and the folders inside them, and nothing else. No photo
// permission is involved: picking the folder is the permission.
class FolderAccess(private val activity: Activity) : MethodChannel.MethodCallHandler {
    // Scanning folders and decoding photos is slow, so it happens on these
    // worker threads, keeping the main thread free to draw the screen.
    private val workers = Executors.newFixedThreadPool(4)
    private val mainThread = Handler(Looper.getMainLooper())

    // The Dart call waiting while the folder picker is open.
    private var pendingPick: MethodChannel.Result? = null

    private val resolver get() = activity.contentResolver

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "list" -> inBackground(result) { chosenFolders() }
            "forget" -> inBackground(result) {
                forget(Uri.parse(call.text("uri")))
                null // Nothing to answer; Kotlin's Unit can't cross to Dart.
            }
            "scan" -> inBackground(result) { scan(Uri.parse(call.text("uri"))) }
            "mediaIds" -> inBackground(result) {
                call.texts("uris").map { mediaId(Uri.parse(it)) }
            }
            "image" -> inBackground(result) {
                image(
                    Uri.parse(call.text("uri")),
                    call.number("maxWidth"),
                    call.number("maxHeight"),
                    call.number("quality"),
                )
            }
            else -> result.notImplemented()
        }
    }

    // Arguments come over a channel, so check them rather than trust them: a
    // missing or wrong-typed one becomes a clear error for Dart, not a crash.
    private fun MethodCall.text(name: String): String =
        argument<String>(name) ?: throw IllegalArgumentException("Missing '$name'.")

    private fun MethodCall.texts(name: String): List<String> =
        argument<List<String>>(name) ?: throw IllegalArgumentException("Missing '$name'.")

    private fun MethodCall.number(name: String): Int =
        argument<Int>(name) ?: throw IllegalArgumentException("Missing '$name'.")

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "The folder picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            // Start in DCIM, where the camera's photos usually are.
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE, "primary:DCIM"),
            )
        }
        try {
            pendingPick = result
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: Exception) {
            pendingPick = null
            result.error("failed", e.message, null)
        }
    }

    // The folder picker's answer. Returns false if it wasn't ours.
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null) // The user backed out.
            return true
        }
        try {
            // Keep the access after the app closes; otherwise it ends with it.
            resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            result.error("failed", e.message, null)
            return true
        }
        inBackground(result) { describe(tree) }
        return true
    }

    // Folders the user has shared, newest first. Android remembers them for
    // the app (persisted permissions), so there's nothing to store here.
    private fun chosenFolders(): List<Map<String, Any?>> =
        resolver.persistedUriPermissions
            .filter { it.isReadPermission && DocumentsContract.isTreeUri(it.uri) }
            .sortedByDescending { it.persistedTime }
            .map { describe(it.uri) }

    private fun forget(tree: Uri) {
        resolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    // A folder's name and where it is, e.g. "Camera" at "DCIM/Camera".
    private fun describe(tree: Uri): Map<String, Any?> {
        val id = DocumentsContract.getTreeDocumentId(tree)
        val path = id.substringAfter(':', "")
        val name = displayName(DocumentsContract.buildDocumentUriUsingTree(tree, id))
            ?: path.substringAfterLast('/').ifEmpty { id }
        return mapOf("uri" to tree.toString(), "name" to name, "path" to path)
    }

    private fun displayName(document: Uri): String? = try {
        resolver.query(document, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        null // Moved or deleted since it was chosen.
    }

    // Every photo in the folder and the folders inside it. Hidden files and
    // folders (names starting with a dot) are skipped, including the
    // .trashed- files Android keeps for photos in its trash.
    private fun scan(tree: Uri): List<Map<String, Any?>> {
        val photos = ArrayList<Map<String, Any?>>()
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val folders = ArrayDeque<Pair<String, String>>() // Document id, name.
        folders.add(rootId to (describe(tree)["name"] as String))
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )
        while (folders.isNotEmpty()) {
            val (folderId, folderName) = folders.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, folderId)
            resolver.query(children, columns, null, null, null)?.use { row ->
                while (row.moveToNext()) {
                    val id = row.getString(0) ?: continue
                    val name = row.getString(1) ?: continue
                    val mime = row.getString(2) ?: continue
                    if (name.startsWith(".")) continue
                    if (mime == Document.MIME_TYPE_DIR) {
                        folders.add(id to name)
                    } else if (mime.startsWith("image/")) {
                        photos.add(
                            mapOf(
                                "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id)
                                    .toString(),
                                "id" to id,
                                "name" to name,
                                "size" to if (row.isNull(3)) null else row.getLong(3),
                                "modified" to if (row.isNull(4)) null else row.getLong(4),
                                "folderId" to folderId,
                                "folderName" to folderName,
                            ),
                        )
                    }
                }
            }
        }
        return photos
    }

    // The photo's MediaStore id, the same id the gallery (and folder-less
    // mode) uses, or null if Android hasn't indexed the file. The trash works
    // by MediaStore id.
    private fun mediaId(document: Uri): String? = try {
        MediaStore.getMediaUri(activity, document)?.let { ContentUris.parseId(it).toString() }
    } catch (e: Exception) {
        null
    }

    // Decodes a photo to fit within maxWidth x maxHeight, keeping its shape
    // and applying its rotation (HEIC too), and hands it over as a JPEG. A
    // huge photo is never decoded at full size, so it can't exhaust memory.
    private fun image(document: Uri, maxWidth: Int, maxHeight: Int, quality: Int): ByteArray {
        val source = ImageDecoder.createSource(resolver, document)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val width = info.size.width
            val height = info.size.height
            val scale = min(1.0, min(maxWidth.toDouble() / width, maxHeight.toDouble() / height))
            if (scale < 1.0) {
                decoder.setTargetSize(
                    max(1, (width * scale).roundToInt()),
                    max(1, (height * scale).roundToInt()),
                )
            }
            // An ordinary in-memory bitmap: the default kind lives in graphics
            // memory and can't be compressed.
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        try {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            return out.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    // Runs work on a worker thread and answers Dart on the main thread, which
    // is the only one allowed to.
    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        workers.execute {
            try {
                val value = work()
                mainThread.post { result.success(value) }
            } catch (e: Throwable) { // Throwable: running out of memory too.
                mainThread.post { result.error("failed", e.message, null) }
            }
        }
    }

    fun close() = workers.shutdown()

    private companion object {
        const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"
        const val PICK_REQUEST = 41010
    }
}
