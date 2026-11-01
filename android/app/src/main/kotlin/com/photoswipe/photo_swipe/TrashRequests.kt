package com.photoswipe.photo_swipe

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Android's own prompts for moving photos to the trash, bringing them back,
// and erasing them for good. Photos are given by MediaStore id, and each
// address is built straight from the id rather than looked up: Android hides
// trashed photos from lookups, and in folder mode the app has no photo
// permission to look anything up with. Each prompt covers a whole batch, and
// nothing changes unless the user allows it there.
class TrashRequests(private val activity: Activity) : MethodChannel.MethodCallHandler {
    // The ids asked about and the Dart call waiting for the answer, while
    // Android's prompt is on screen.
    private var pending: Pair<List<String>, MethodChannel.Result>? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val resolver = activity.contentResolver
        when (call.method) {
            "trash" -> ask(call, result) { MediaStore.createTrashRequest(resolver, it, true) }
            "restore" -> ask(call, result) { MediaStore.createTrashRequest(resolver, it, false) }
            "deleteForever" -> ask(call, result) { MediaStore.createDeleteRequest(resolver, it) }
            else -> result.notImplemented()
        }
    }

    private fun ask(
        call: MethodCall,
        result: MethodChannel.Result,
        request: (List<Uri>) -> PendingIntent,
    ) {
        if (pending != null) {
            result.error("busy", "Android is already asking about other photos.", null)
            return
        }
        try {
            val ids = call.argument<List<String>>("ids")!!
            val uris = ids.map {
                ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    it.toLong(),
                )
            }
            val prompt = request(uris)
            pending = ids to result
            activity.startIntentSenderForResult(prompt.intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            result.error("failed", e.message, null)
        }
    }

    // Android's answer to a prompt. Returns false if it wasn't one of ours.
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val (ids, result) = pending ?: return true
        pending = null
        // All or nothing: the prompt covers the whole batch.
        result.success(if (resultCode == Activity.RESULT_OK) ids else emptyList())
        return true
    }

    private companion object {
        // Any number, as long as it's different from the app's other ones.
        const val REQUEST_CODE = 41001
    }
}
