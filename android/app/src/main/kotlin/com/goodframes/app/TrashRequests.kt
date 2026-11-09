package com.goodframes.app

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Android's own prompts for moving photos to the trash, bringing them back,
// erasing them for good, and moving them into a gallery folder. Photos are given by MediaStore id, and each
// address is built straight from the id rather than looked up: Android hides
// trashed photos from lookups, and in folder mode the app has no photo
// permission to look anything up with. Each prompt covers a whole batch, and
// nothing changes unless the user allows it there.
class TrashRequests(private val activity: Activity) : MethodChannel.MethodCallHandler {
    // The ids asked about and the Dart call waiting for the answer, while
    // Android's prompt is on screen.
    private var pending: Pair<List<String>, MethodChannel.Result>? = null

    // Set only while a "moveToFolder" prompt is on screen: the folder (inside
    // Pictures) the allowed photos are then moved into.
    private var pendingFolder: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val resolver = activity.contentResolver
        when (call.method) {
            "trash" -> ask(call, result) { MediaStore.createTrashRequest(resolver, it, true) }
            "restore" -> ask(call, result) { MediaStore.createTrashRequest(resolver, it, false) }
            "deleteForever" -> ask(call, result) { MediaStore.createDeleteRequest(resolver, it) }
            "moveToFolder" -> {
                // Checked here as well as in Dart: this is what decides where
                // files end up, so it must never trust its caller.
                val folder = call.argument<String>("folder")
                if (folder == null || !validFolder(folder)) {
                    result.error("failed", "That isn't a usable folder name.", null)
                } else {
                    ask(call, result, folder) { MediaStore.createWriteRequest(resolver, it) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun ask(
        call: MethodCall,
        result: MethodChannel.Result,
        folder: String? = null,
        request: (List<Uri>) -> PendingIntent,
    ) {
        if (pending != null) {
            result.error("busy", "Android is already asking about other photos.", null)
            return
        }
        try {
            val ids = call.argument<List<String>>("ids")
                ?: throw IllegalArgumentException("Missing 'ids'.")
            val uris = ids.map {
                ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    it.toLong(),
                )
            }
            val prompt = request(uris)
            pending = ids to result
            pendingFolder = folder
            activity.startIntentSenderForResult(prompt.intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            pendingFolder = null
            result.error("failed", e.message, null)
        }
    }

    // Android's answer to a prompt. Returns false if it wasn't one of ours.
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val (ids, result) = pending ?: return true
        val folder = pendingFolder
        pending = null
        pendingFolder = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(emptyList<String>())
        } else if (folder == null) {
            // All or nothing: the prompt covers the whole batch.
            result.success(ids)
        } else {
            moveInto(folder, ids, result)
        }
        return true
    }

    // Allowed to change these photos: moves each into Pictures/<folder> by
    // changing where MediaStore says it lives. Android moves the file, and
    // the photo keeps its id. Done off the main thread, one photo at a time,
    // so one that can't move (for instance a clash of names) doesn't stop
    // the rest; only the ids that did move are reported back.
    private fun moveInto(folder: String, ids: List<String>, result: MethodChannel.Result) {
        Thread {
            val moved = ids.filter { id ->
                try {
                    val uri = ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id.toLong(),
                    )
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/$folder/")
                    }
                    activity.contentResolver.update(uri, values, null, null) > 0
                } catch (e: Exception) {
                    false
                }
            }
            activity.runOnUiThread { result.success(moved) }
        }.start()
    }

    // A single folder name directly inside Pictures: no slashes, no tricks.
    private fun validFolder(name: String): Boolean =
        name.isNotBlank() &&
            name == name.trim() &&
            name.length <= 64 &&
            !name.startsWith(".") &&
            name.none { it in "/\\:*?\"<>|" || it.isISOControl() }

    private companion object {
        // Any number, as long as it's different from the app's other ones.
        const val REQUEST_CODE = 41001
    }
}
