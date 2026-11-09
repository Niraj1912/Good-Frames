import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:good_frames/models/chosen_folder.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/trashed_photo.dart';

/// The app's own Android code (TrashRequests.kt and FolderAccess.kt),
/// reached through platform channels: named pipes between Dart and Kotlin.
abstract final class AndroidMedia {
  static const _trash = MethodChannel('goodframes/trash');
  static const _folders = MethodChannel('goodframes/folders');

  /// Asks Android to move photos (by MediaStore id) to its trash. Android
  /// shows one prompt for the batch; returns every id, or none if the user
  /// said no.
  static Future<Set<String>> trash(List<String> ids) => _ask('trash', ids);

  /// Brings photos back from Android's trash, the same way.
  static Future<Set<String>> restore(List<String> ids) => _ask('restore', ids);

  /// Erases photos for good, after Android's own "delete?" prompt.
  static Future<Set<String>> deleteForever(List<String> ids) =>
      _ask('deleteForever', ids);

  static Future<Set<String>> _ask(String method, List<String> ids) async {
    if (ids.isEmpty) return {};
    final done = await _trash.invokeListMethod<String>(method, {'ids': ids});
    return {...?done};
  }

  /// Asks Android for permission to change [ids], then moves them into
  /// DCIM/MyAlbums/[folder]. One prompt for the batch; returns the ids that
  /// moved, or none if the user said no.
  static Future<Set<String>> moveToFolder(
    List<String> ids,
    String folder,
  ) async {
    if (ids.isEmpty) return {};
    final done = await _trash.invokeListMethod<String>('moveToFolder', {
      'ids': ids,
      'folder': folder,
    });
    return {...?done};
  }

  /// The folders photos are in under DCIM and Pictures, as paths like
  /// `Pictures/Screenshots`. Empty if the app can't see photos.
  static Future<List<String>> existingFolders() async => [
    ...?await _trash.invokeListMethod<String>('listFolders'),
  ];

  /// Opens Android's folder picker. Returns the folder, or null if the user
  /// backed out.
  static Future<ChosenFolder?> pickFolder() async {
    final folder = await _folders.invokeMapMethod<String, Object?>('pick');
    return folder == null ? null : _toFolder(folder);
  }

  static Future<List<ChosenFolder>> chosenFolders() async {
    final folders =
        await _folders.invokeListMethod<Map<Object?, Object?>>('list') ?? [];
    return [for (final folder in folders) _toFolder(folder)];
  }

  static Future<void> forgetFolder(ChosenFolder folder) =>
      _folders.invokeMethod<void>('forget', {'uri': folder.uri});

  /// Every photo in [folder] and the folders inside it.
  static Future<List<FoundPhoto>> scanFolder(ChosenFolder folder) async {
    final rows =
        await _folders.invokeListMethod<Map<Object?, Object?>>('scan', {
          'uri': folder.uri,
        }) ??
        [];
    return [
      for (final row in rows)
        FoundPhoto(
          uri: row['uri']! as String,
          documentId: row['id']! as String,
          name: row['name']! as String,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (row['modified'] as int?) ?? 0,
          ),
          folderId: row['folderId']! as String,
          folderName: row['folderName']! as String,
          sizeBytes: row['size'] as int?,
        ),
    ];
  }

  /// The MediaStore id of each photo in [uris], in the same order: null for
  /// any Android hasn't indexed.
  static Future<List<String?>> mediaIds(List<String> uris) async {
    if (uris.isEmpty) return [];
    return await _folders.invokeListMethod<String?>('mediaIds', {
          'uris': uris,
        }) ??
        [];
  }

  /// The photo at [uri] as a JPEG that fits within [maxWidth] x [maxHeight].
  static Future<Uint8List?> image(
    String uri, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
  }) => _folders.invokeMethod<Uint8List>('image', {
    'uri': uri,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
    'quality': quality,
  });

  static ChosenFolder _toFolder(Map<Object?, Object?> folder) => ChosenFolder(
    uri: folder['uri']! as String,
    name: folder['name']! as String,
    path: folder['path']! as String,
  );
}

/// A photo found in a chosen folder, before Android is asked for its id.
class FoundPhoto {
  const FoundPhoto({
    required this.uri,
    required this.documentId,
    required this.name,
    required this.modified,
    required this.folderId,
    required this.folderName,
    this.sizeBytes,
  });

  /// Where to read it, through the access the folder was shared with.
  final String uri;

  /// The same for every route to the file, so a photo inside two chosen
  /// folders (DCIM, and DCIM/Camera too) can be counted once.
  final String documentId;

  final String name;
  final DateTime modified;

  /// The folder it's directly in, which is its album.
  final String folderId;
  final String folderName;

  final int? sizeBytes;
}

/// A photo from a chosen folder, decoded by the app's Android code to fit
/// within [maxWidth] x [maxHeight] (keeping its shape and rotation), so a
/// huge photo never has to fit in memory whole.
@immutable
class SharedPhotoImage extends ImageProvider<SharedPhotoImage> {
  const SharedPhotoImage(
    this.uri, {
    required this.maxWidth,
    required this.maxHeight,
    this.quality = 85,
  });

  final String uri;
  final int maxWidth;
  final int maxHeight;

  /// JPEG quality for the hand-over from Android to Flutter.
  final int quality;

  @override
  Future<SharedPhotoImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    SharedPhotoImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: uri,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await AndroidMedia.image(
      uri,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
    );
    if (bytes == null || bytes.isEmpty) {
      throw StateError("Couldn't open the photo at $uri");
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is SharedPhotoImage &&
      other.uri == uri &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(uri, maxWidth, maxHeight, quality);
}

/// The trash, done the same way for every Android photo source: Android's
/// own trash, by MediaStore id, with a small copy of each photo kept for
/// the Recently deleted screen.
mixin AndroidTrash {
  /// Where the small copies of trashed photos are kept.
  Directory get thumbnailFolder;

  /// A small JPEG of [photo], or null if one can't be made.
  Future<List<int>?> trashThumbnail(Photo photo);

  bool get confirmsTrashItself => true;

  String get trashExplanation =>
      'Android keeps trashed photos for about 30 days before removing them '
      'for good.';

  Duration? get trashKeepsFor => const Duration(days: 30);

  Future<List<TrashedPhoto>> moveToTrash(
    List<Photo> photos, {
    void Function(int done, int total)? onProgress,
  }) async {
    // Save a small copy of each photo first. Once a photo is in the trash,
    // Android hides it even from this app, so the Recently deleted screen
    // would have nothing to show. Eight at a time: Android makes them on
    // background threads, so asking for several at once is much faster.
    await thumbnailFolder.create(recursive: true);
    final thumbnails = <String, String>{};
    for (var start = 0; start < photos.length; start += 8) {
      final batch = photos.skip(start).take(8).toList();
      await Future.wait([
        for (final photo in batch)
          _saveThumbnail(photo).then((path) {
            if (path != null) thumbnails[photo.id] = path;
          }),
      ]);
      onProgress?.call(start + batch.length, photos.length);
    }

    final moved = await AndroidMedia.trash([
      for (final photo in photos) photo.id,
    ]);

    final now = DateTime.now();
    final trashed = <TrashedPhoto>[];
    for (final photo in photos) {
      final thumbnail = thumbnails[photo.id];
      if (moved.contains(photo.id)) {
        trashed.add(
          TrashedPhoto(
            photoId: photo.id,
            name: photo.name,
            trashedAt: now,
            thumbnailPath: thumbnail,
            sizeBytes: photo.sizeBytes,
          ),
        );
      } else if (thumbnail != null) {
        // Not trashed after all (the user cancelled), so drop the copy.
        await File(thumbnail).delete();
      }
    }
    return trashed;
  }

  Future<Set<String>> restoreFromTrash(List<TrashedPhoto> photos) async {
    final restored = await AndroidMedia.restore([
      for (final photo in photos) photo.photoId,
    ]);
    await forgetTrashed([
      for (final photo in photos)
        if (restored.contains(photo.photoId)) photo,
    ]);
    return restored;
  }

  Future<Set<String>> deleteForever(List<TrashedPhoto> photos) async {
    final deleted = await AndroidMedia.deleteForever([
      for (final photo in photos) photo.photoId,
    ]);
    await forgetTrashed([
      for (final photo in photos)
        if (deleted.contains(photo.photoId)) photo,
    ]);
    return deleted;
  }

  bool get canMoveToFolders => true;

  Future<List<String>> existingFolders() => AndroidMedia.existingFolders();

  Future<Set<String>> moveToFolder(List<Photo> photos, String folder) =>
      AndroidMedia.moveToFolder([for (final photo in photos) photo.id], folder);

  Future<void> forgetTrashed(List<TrashedPhoto> photos) async {
    for (final photo in photos) {
      if (photo.thumbnailPath case final path?) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  // Writes the small copy of [photo] and returns its path, or null if
  // Android couldn't make one.
  Future<String?> _saveThumbnail(Photo photo) async {
    try {
      final bytes = await trashThumbnail(photo);
      if (bytes == null) return null;
      final file = File(p.join(thumbnailFolder.path, '${photo.id}.jpg'));
      await file.writeAsBytes(bytes);
      return file.path;
    } on PlatformException {
      return null; // A broken file: trash it anyway, just without a picture.
    }
  }
}
