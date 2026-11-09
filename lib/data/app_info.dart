import 'package:flutter/services.dart';

/// Facts about this copy of the app, for the About part of Settings.
abstract final class AppInfo {
  static const _channel = MethodChannel('goodframes/app');

  /// Its version, such as "1.0.0 (1)": the name people see, then the number
  /// Android compares to tell which build is newer. Read from Android, so it
  /// always matches the installed APK. Null where the platform can't say:
  /// the Windows build has no code answering this channel.
  static Future<String?> version() async {
    try {
      return await _channel.invokeMethod<String>('version');
    } on MissingPluginException {
      return null;
    }
  }
}
