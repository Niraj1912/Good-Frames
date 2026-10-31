import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_swipe/data/android_photo_repository.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/folder_photo_repository.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/screens/access_screen.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

/// The folder the Windows build reads. To use another one:
/// `flutter run -d windows --dart-define=PHOTO_ROOT=D:\other\folder`
const _photoRoot = String.fromEnvironment(
  'PHOTO_ROOT',
  defaultValue: r'E:\test-photos',
);

Future<void> main() async {
  // Plugins (path_provider, sqflite) can only be used before runApp after
  // this call.
  WidgetsFlutterBinding.ensureInitialized();

  // The only place that decides where photos and decisions live. Everything
  // else just uses the PhotoRepository and DecisionStore it's given.
  final PhotoRepository repository;
  final sqflite.DatabaseFactory databaseFactory;
  if (Platform.isAndroid) {
    repository = AndroidPhotoRepository();
    databaseFactory = sqflite.databaseFactorySqflitePlugin;
  } else {
    repository = FolderPhotoRepository(rootPath: _photoRoot);
    // Windows has no SQLite built in. The FFI version brings its own copy.
    sqflite_ffi.sqfliteFfiInit();
    databaseFactory = sqflite_ffi.databaseFactoryFfi;
  }

  final appFolder = await getApplicationSupportDirectory();
  final store = await DecisionStore.open(
    databaseFactory,
    p.join(appFolder.path, 'decisions.db'),
  );

  runApp(PhotoSwipeApp(repository: repository, store: store));
}

class PhotoSwipeApp extends StatelessWidget {
  const PhotoSwipeApp({
    super.key,
    required this.repository,
    required this.store,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwipeSort',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: AccessScreen(repository: repository, store: store),
    );
  }
}
