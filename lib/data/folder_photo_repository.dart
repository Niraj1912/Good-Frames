import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/photo_order.dart';
import 'package:good_frames/models/trashed_photo.dart';
import 'package:good_frames/widgets/formatting.dart';

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

  /// Where trashed photos go. Never shown as photos.
  static const trashFolderName = '_GoodFrames_Trash';

  /// The name this folder had before the app was renamed. It stays hidden
  /// from scans, so a trash folder left by an older version isn't shown as
  /// photos.
  static const _oldTrashFolderName = '_SwipeSort_Trash';

  static const _allPhotosId = '*all*';

  // The last scan, reused when an album is opened right after the album list
  // loaded. Thrown away whenever this class moves files.
  _Scan? _lastScan;
  int _skippedHeic = 0;

  @override
  String get sourceName => rootPath;

  @override
  String? get notice => _skippedHeic == 0
      ? null
      : 'Skipped ${photoCount(_skippedHeic)} in HEIC format: Windows can\'t '
            'display HEIC. (Android can.)';

  // Desktop apps can read the user's files without asking.
  @override
  Future<AccessStatus> requestAccess() async => AccessStatus.granted;

  @override
  Future<AccessStatus> checkAccess() async => AccessStatus.granted;

  @override
  Future<void> openAccessSettings() async {}

  @override
  Future<void> changeSelectedPhotos() async {}

  // Always scans afresh, so the Reload button picks up new files.
  @override
  Future<List<Album>> albums() async {
    final byFolder = (_lastScan = await _scan()).byFolder;
    if (byFolder.isEmpty) return [];

    final total = byFolder.values.fold(0, (sum, photos) => sum + photos.length);
    final folders = byFolder.keys.toList()..sort();
    Photo newest(Iterable<Photo> photos) =>
        photos.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    return [
      Album(
        id: _allPhotosId,
        name: 'All photos',
        photoCount: total,
        cover: newest(byFolder.values.expand((photos) => photos)),
      ),
      for (final folder in folders)
        Album(
          id: folder,
          name: _albumName(folder),
          photoCount: byFolder[folder]!.length,
          cover: newest(byFolder[folder]!),
        ),
    ];
  }

  @override
  // One page: the folder was already scanned for the album list.
  Stream<List<Photo>> photosIn(
    Album album, {
    PhotoOrder order = PhotoOrder.newestFirst,
  }) async* {
    final byFolder = (_lastScan ??= await _scan()).byFolder;
    final photos = album.id == _allPhotosId
        ? byFolder.values.expand((photos) => photos).toList()
        : [...?byFolder[album.id]];
    yield photos..sort(
      (a, b) => switch (order) {
        PhotoOrder.newestFirst => b.date.compareTo(a.date),
        PhotoOrder.oldestFirst => a.date.compareTo(b.date),
      },
    );
  }

  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      ResizeImage(FileImage(File(photo.id)), width: width);

  // The original file, only shrunk if it's bigger than maxSize.
  @override
  ImageProvider detailImageFor(Photo photo, {int maxSize = 4096}) =>
      ResizeImage(
        FileImage(File(photo.id)),
        width: maxSize,
        height: maxSize,
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );

  @override
  bool get confirmsTrashItself => false;

  @override
  String get trashExplanation =>
      'They go to the $trashFolderName folder inside $rootPath, where you '
      "can move them back. They're only erased if you choose Delete forever.";

  // A plain folder: nothing ever empties it but the user.
  @override
  Duration? get trashKeepsFor => null;

  @override
  Future<List<TrashedPhoto>> moveToTrash(
    List<Photo> photos, {
    void Function(int done, int total)? onProgress,
  }) async {
    final moved = <TrashedPhoto>[];
    for (final (index, photo) in photos.indexed) {
      if (await _moveOneToTrash(photo) case final trashed?) moved.add(trashed);
      onProgress?.call(index + 1, photos.length);
    }
    _lastScan = null; // Files moved, so the last scan is out of date.
    return moved;
  }

  /// Whether [path] is really inside [root]. [p.isWithin] reads the text of
  /// the paths only, so a shortcut (symbolic link) inside the folder that
  /// points somewhere else would pass it. This also follows links and compares
  /// where they truly lead. A file that isn't there yet passes on the text
  /// check alone, since there is nothing to follow.
  @visibleForTesting
  static bool isInside(String root, String path) {
    if (!p.isWithin(root, path)) return false;
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return true;
      }
      final realRoot = Directory(root).resolveSymbolicLinksSync();
      final real = FileSystemEntity.isDirectorySync(path)
          ? Directory(path).resolveSymbolicLinksSync()
          : File(path).resolveSymbolicLinksSync();
      return p.isWithin(realRoot, real);
    } on FileSystemException {
      return false;
    }
  }

  bool _isInside(String root, String path) => isInside(root, path);

  Future<TrashedPhoto?> _moveOneToTrash(Photo photo) async {
    // A photo id is a path, so check it really is inside our folder before
    // touching it. Code that moves files must never trust a path blindly.
    if (!_isInside(rootPath, photo.id)) return null;

    // Keep the folders inside the trash, so Camera/IMG_0001.jpg and
    // Screenshots/IMG_0001.jpg can't collide there.
    final relative = p.relative(photo.id, from: rootPath);
    final target = await _unusedPath(
      p.join(rootPath, trashFolderName, relative),
    );
    try {
      await Directory(p.dirname(target)).create(recursive: true);
      // Same drive, so this is an instant rename, not a copy.
      await File(photo.id).rename(target);
    } on FileSystemException {
      // Open in another program, read-only, or already gone: leave it, and
      // it stays marked so the user can try again.
      return null;
    }
    return TrashedPhoto(
      photoId: photo.id,
      name: photo.name,
      trashedAt: DateTime.now(),
      // The file itself is still viewable in the trash folder.
      thumbnailPath: target,
      trashPath: target,
      sizeBytes: photo.sizeBytes,
    );
  }

  @override
  Future<Set<String>> restoreFromTrash(List<TrashedPhoto> photos) async {
    final trashFolder = p.join(rootPath, trashFolderName);
    final restored = <String>{};
    for (final photo in photos) {
      final from = photo.trashPath;
      // The same rule as trashing: only move files from where we put them,
      // back to somewhere inside our folder.
      if (from == null ||
          !_isInside(trashFolder, from) ||
          !_isInside(rootPath, photo.photoId)) {
        continue;
      }
      // Something new may have taken the old name since; don't overwrite it.
      final target = await _unusedPath(photo.photoId);
      try {
        await Directory(p.dirname(target)).create(recursive: true);
        await File(from).rename(target);
        restored.add(photo.photoId);
      } on FileSystemException {
        // The user emptied the trash folder themselves, or the file is open.
      }
    }
    _lastScan = null;
    return restored;
  }

  @override
  Future<Set<String>> deleteForever(List<TrashedPhoto> photos) async {
    final trashFolder = p.join(rootPath, trashFolderName);
    final deleted = <String>{};
    for (final photo in photos) {
      final path = photo.trashPath;
      // Only ever erase files inside our own trash folder, never a photo
      // still in the library, whatever the database says.
      if (path == null || !_isInside(trashFolder, path)) continue;
      try {
        await File(path).delete();
        deleted.add(photo.photoId);
      } on PathNotFoundException {
        // The user already emptied it from the folder: it's gone either way.
        deleted.add(photo.photoId);
      } on FileSystemException {
        // Open in another program. Leave it in the trash.
      }
    }
    return deleted;
  }

  // Nothing extra is kept for trashed photos here.
  @override
  Future<void> forgetTrashed(List<TrashedPhoto> photos) async {}

  // [path] itself, or "name (2).jpg", "name (3).jpg"... if that name is
  // already taken. Moving a file must never overwrite another.
  Future<String> _unusedPath(String path) async {
    if (!await File(path).exists()) return path;
    final base = p.withoutExtension(path);
    final extension = p.extension(path);
    for (var n = 2; ; n++) {
      final candidate = '$base ($n)$extension';
      if (!await File(candidate).exists()) return candidate;
    }
  }

  /// Scans [rootPath] on a background isolate (a separate worker). Listing
  /// 10,000 files takes a moment; doing it on the main isolate would freeze
  /// the screen while it runs.
  Future<_Scan> _scan() async {
    final rootPath = this.rootPath; // Send the string, not the whole object.
    final scan = await Isolate.run(() => _scanFolder(rootPath));
    _skippedHeic = scan.skippedHeic;
    return scan;
  }

  String _albumName(String folder) {
    final relative = p.relative(folder, from: rootPath);
    return relative == '.' ? p.basename(rootPath) : relative;
  }
}

typedef _Scan = ({Map<String, List<Photo>> byFolder, int skippedHeic});

/// Finds every photo under [rootPath], grouped by the folder it's in, and
/// counts the HEIC files it had to skip. Runs on a background isolate, so
/// plain synchronous file calls are fine here, and much faster than
/// thousands of separate awaits.
_Scan _scanFolder(String rootPath) {
  final byFolder = <String, List<Photo>>{};
  var skippedHeic = 0;
  final root = Directory(rootPath);
  if (!root.existsSync()) return (byFolder: byFolder, skippedHeic: 0);

  final folders = [root];
  while (folders.isNotEmpty) {
    final folder = folders.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = folder.listSync(followLinks: false);
    } on FileSystemException {
      continue; // A folder we aren't allowed to read: skip it, don't crash.
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;
      if (entry is Directory) {
        if (name != FolderPhotoRepository.trashFolderName &&
            name != FolderPhotoRepository._oldTrashFolderName) {
          folders.add(entry);
        }
        continue;
      }
      if (entry is! File) continue;

      final extension = p.extension(name).toLowerCase();
      if (extension == '.heic' || extension == '.heif') skippedHeic++;
      if (!FolderPhotoRepository.supportedExtensions.contains(extension)) {
        continue;
      }
      final stat = entry.statSync();
      (byFolder[folder.path] ??= []).add(
        Photo(
          // The full path is unique even when two folders hold the same
          // file name, like Camera/IMG_0001.jpg and Screenshots/IMG_0001.jpg.
          id: entry.path,
          name: name,
          date: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
  }
  return (byFolder: byFolder, skippedHeic: skippedHeic);
}
