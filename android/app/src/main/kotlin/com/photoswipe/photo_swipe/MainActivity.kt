package com.photoswipe.photo_swipe

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// The app's own Android code, for what the photo_manager plugin can't do:
//
// * TrashRequests.kt: Android's trash, restore and delete-forever prompts.
// * FolderAccess.kt: folder mode, where the user shares chosen folders
//   instead of every photo.
// * The app's version, for Settings (below).
//
// Dart reaches them through MethodChannels (see lib/data/android_media.dart):
// named pipes between Flutter and Android code.
class MainActivity : FlutterActivity() {
    private val trash = TrashRequests(this)
    private val folders = FolderAccess(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "swipesort/trash").setMethodCallHandler(trash)
        MethodChannel(messenger, "swipesort/folders").setMethodCallHandler(folders)
        MethodChannel(messenger, "swipesort/app").setMethodCallHandler { call, result ->
            if (call.method == "version") {
                val info = packageInfo()
                // The name people see, then the number Android compares.
                result.success("${info.versionName} (${info.longVersionCode})")
            } else {
                result.notImplemented()
            }
        }
    }

    // Android 13 replaced the flags number with an object; older versions
    // only understand the number.
    private fun packageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (trash.onActivityResult(requestCode, resultCode)) return
        if (folders.onActivityResult(requestCode, resultCode, data)) return
        // Not ours: photo_manager's own prompts end up here.
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        folders.close()
        super.onDestroy()
    }
}
