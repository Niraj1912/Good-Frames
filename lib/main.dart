import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_swipe/data/android_folder_photo_repository.dart';
import 'package:photo_swipe/data/android_photo_repository.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/folder_photo_repository.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/screens/access_screen.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
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

  // Inter is free on one condition: its licence goes with the app, on the
  // open-source licences page in Settings.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Inter'], text);
  });

  final appFolder = await getApplicationSupportDirectory();

  // The only place that decides where photos and decisions live. Everything
  // else just uses the PhotoRepository and DecisionStore it's given.
  final PhotoRepository repository;
  ChosenFoldersRepository? folders; // Only where the user can pick folders.
  final sqflite.DatabaseFactory databaseFactory;
  if (Platform.isAndroid) {
    final thumbnails = Directory(p.join(appFolder.path, 'trash_thumbnails'));
    repository = AndroidPhotoRepository(thumbnailFolder: thumbnails);
    folders = AndroidFolderPhotoRepository(thumbnailFolder: thumbnails);
    databaseFactory = sqflite.databaseFactorySqflitePlugin;
  } else {
    repository = FolderPhotoRepository(rootPath: _photoRoot);
    // Windows has no SQLite built in. The FFI version brings its own copy.
    sqflite_ffi.sqfliteFfiInit();
    databaseFactory = sqflite_ffi.databaseFactoryFfi;
  }

  final store = await DecisionStore.open(
    databaseFactory,
    p.join(appFolder.path, 'decisions.db'),
  );

  // Loaded before the first frame, so a dark theme chosen in Settings never
  // flashes light first.
  final settings = await Settings.load(store);

  runApp(
    PhotoSwipeApp(
      repository: repository,
      folders: folders,
      store: store,
      settings: settings,
    ),
  );
}

class PhotoSwipeApp extends StatelessWidget {
  const PhotoSwipeApp({
    super.key,
    required this.repository,
    required this.store,
    required this.settings,
    this.folders,
  });

  final PhotoRepository repository;
  final ChosenFoldersRepository? folders;
  final DecisionStore store;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a setting changes, so a new theme shows at once. The
    // screens are built once, outside, so they keep their place.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, home) => MaterialApp(
        title: 'Good Frames',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.theme,
        debugShowCheckedModeBanner: false,
        // One background under every page, so it stays still as they change.
        builder: (context, navigator) => GlassBackground(child: navigator!),
        home: home,
      ),
      child: AccessScreen(
        repository: repository,
        folders: folders,
        store: store,
        settings: settings,
      ),
    );
  }
}
