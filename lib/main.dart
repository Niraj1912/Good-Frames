import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:photo_swipe/data/android_photo_repository.dart';
import 'package:photo_swipe/data/folder_photo_repository.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/screens/access_screen.dart';

/// The folder the Windows build reads. To use another one:
/// `flutter run -d windows --dart-define=PHOTO_ROOT=D:\other\folder`
const _photoRoot = String.fromEnvironment(
  'PHOTO_ROOT',
  defaultValue: r'E:\test-photos',
);

void main() {
  // The only place that decides where photos come from. Everything else
  // just uses the PhotoRepository interface.
  final PhotoRepository repository = Platform.isAndroid
      ? AndroidPhotoRepository()
      : FolderPhotoRepository(rootPath: _photoRoot);

  runApp(PhotoSwipeApp(repository: repository));
}

class PhotoSwipeApp extends StatelessWidget {
  const PhotoSwipeApp({super.key, required this.repository});

  final PhotoRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwipeSort',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: AccessScreen(repository: repository),
    );
  }
}
