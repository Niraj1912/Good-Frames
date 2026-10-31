import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';

/// Reads photos from a folder on disk. The Windows build uses it, so most of
/// the app can be developed and tested on a laptop.
///
/// Every folder under [rootPath] that directly holds photos becomes an album,
/// the same way Android groups its gallery by folder.
class FolderPhotoRepository implements PhotoRepository {
  FolderPhotoRepository({required this.rootPath});

  final String rootPath;

  /// Formats Flutter can decode on every platform. HEIC is left out because
  /// Windows can't display it.
  static const supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  };

  /// Where deleted photos will go (Phase 4). Never shown as photos.
  static const trashFolderName = '_SwipeSort_Trash';

  static const _allPhotosId = '*all*';

  @override
  String get sourceName => rootPath;

  // Desktop apps can read the user's files without asking.
  @override
  Future<AccessStatus> requestAccess() async => AccessStatus.granted;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<void> changeSelectedPhotos() async {}

  @override
  Future<List<Album>> albums() async {
    final byFolder = await _scan();
    if (byFolder.isEmpty) return [];

    final total = byFolder.values.fold(0, (sum, photos) => sum + photos.length);
    final folders = byFolder.keys.toList()..sort();
    return [
      Album(id: _allPhotosId, name: 'All photos', photoCount: total),
      for (final folder in folders)
        Album(
          id: folder,
          name: _albumName(folder),
          photoCount: byFolder[folder]!.length,
        ),
    ];
  }

  @override
  Future<List<Photo>> photosIn(Album album) async {
    final byFolder = await _scan();
    final photos = album.id == _allPhotosId
        ? byFolder.values.expand((photos) => photos).toList()
        : byFolder[album.id] ?? [];
    return photos..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      ResizeImage(FileImage(File(photo.id)), width: width);

  /// Finds every photo under [rootPath], grouped by the folder it's in.
  /// Rescans on every call: simple, and fast enough for a test folder.
  Future<Map<String, List<Photo>>> _scan() async {
    final root = Directory(rootPath);
    if (!await root.exists()) return {};

    final byFolder = <String, List<Photo>>{};
    final entries = root
        .list(recursive: true, followLinks: false)
        // Skip folders we aren't allowed to read instead of crashing.
        .handleError((_) {}, test: (error) => error is FileSystemException);
    await for (final entry in entries) {
      if (entry is! File || !_isPhoto(entry.path)) continue;
      final stat = await entry.stat();
      final folder = p.dirname(entry.path);
      (byFolder[folder] ??= []).add(
        Photo(
          // The full path is unique even when two folders hold the same
          // file name, like Camera/IMG_0001.jpg and Screenshots/IMG_0001.jpg.
          id: entry.path,
          name: p.basename(entry.path),
          date: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    return byFolder;
  }

  bool _isPhoto(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;
    final folders = p.split(p.relative(path, from: rootPath));
    if (folders.contains(trashFolderName)) return false;
    return supportedExtensions.contains(p.extension(name).toLowerCase());
  }

  String _albumName(String folder) {
    final relative = p.relative(folder, from: rootPath);
    return relative == '.' ? p.basename(rootPath) : relative;
  }
}
