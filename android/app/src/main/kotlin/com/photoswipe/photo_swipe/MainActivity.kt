package com.photoswipe.photo_swipe

import android.content.ContentUris
import android.content.Intent
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// The app's only Android code of its own: erasing photos that are already in
// the trash. photo_manager can't, because it looks each photo up first and
// Android hides trashed photos from lookups. Here the photo's address is
// built straight from its id instead, the way photo_manager's restore does.
//
// Dart calls this through a MethodChannel (see AndroidPhotoRepository): a
// named pipe between Flutter and Android code.
class MainActivity : FlutterActivity() {
    // The ids being deleted and the Dart call waiting for the answer, while
    // Android's "permanently delete?" prompt is on screen.
    private var pending: Pair<List<String>, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "swipesort/trash")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteForever" ->
                        deleteForever(call.argument<List<String>>("ids")!!, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun deleteForever(ids: List<String>, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Already asking to delete other photos.", null)
            return
        }
        try {
            val uris = ids.map {
                ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    it.toLong(),
                )
            }
            // Android shows its own prompt; nothing is erased unless the user
            // allows it there. The answer arrives in onActivityResult.
            val request = MediaStore.createDeleteRequest(contentResolver, uris)
            pending = ids to result
            startIntentSenderForResult(request.intentSender, DELETE_REQUEST, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            result.error("failed", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != DELETE_REQUEST) {
            // Not ours: photo_manager's trash and restore prompts end up here.
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val (ids, result) = pending ?: return
        pending = null
        // All or nothing: the prompt covers the whole batch.
        result.success(if (resultCode == RESULT_OK) ids else emptyList())
    }

    private companion object {
        // Any number, as long as it's different from photo_manager's.
        const val DELETE_REQUEST = 41001
    }
}
