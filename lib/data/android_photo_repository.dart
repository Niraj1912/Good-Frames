import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/trashed_photo.dart';

/// Reads the phone's gallery through Android's MediaStore, using the
/// photo_manager plugin.
class AndroidPhotoRepository implements PhotoRepository {
  AndroidPhotoRepository({required this.thumbnailFolder});

  /// Where small copies of trashed photos are kept for the Recently deleted
  /// screen.
  final Directory thumbnailFolder;

  // photo_manager's own objects, kept so they can be found again by id.
  final _albums = <String, AssetPathEntity>{};
  final _assets = <String, AssetEntity>{};

  @override
  String get sourceName => "your phone's gallery";

  @override
  String? get notice => null;

  @override
  Future<AccessStatus> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        // Photos only. Asking for videos too would need more permissions.
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    return switch (state) {
      PermissionState.authorized => AccessStatus.granted,
      PermissionState.limited => AccessStatus.limited,
      _ => AccessStatus.denied,
    };
  }

  @override
  Future<void> openAccessSettings() => PhotoManager.openSetting();

  // Shows Android 14's system photo picker so the user can share more photos.
  @override
  Future<void> changeSelectedPhotos() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<List<Album>> albums() async {
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    final albums = <Album>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      _albums[path.id] = path;
      // The newest photo is first, so a one-photo page is the cover.
      final first = await path.getAssetListRange(start: 0, end: 1);
      albums.add(
        Album(
          id: path.id,
          name: path.isAll ? 'All photos' : path.name,
          photoCount: count,
          cover: first.isEmpty ? null : _toPhoto(first.single),
        ),
      );
    }
    return albums;
  }

  // Asking Android for 10,000 photos in one go took 17 seconds, so they come
  // in pages: a small first one, so sorting can start almost at once, then
  // bigger ones in the background.
  @override
  Stream<List<Photo>> photosIn(Album album) async* {
    final path = _albums[album.id]!;
    final count = await path.assetCountAsync;
    var start = 0;
    var pageSize = 200;
    while (start < count) {
      final end = min(start + pageSize, count);
      final assets = await path.getAssetListRange(start: start, end: end);
      yield [for (final asset in assets) _toPhoto(asset)];
      start = end;
      pageSize = 1000;
    }
  }

  // A thumbnail at screen width, never the full 12-megapixel original, so
  // the phone doesn't run out of memory. Android keeps the aspect ratio.
  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      AssetEntityImageProvider(
        _assets[photo.id]!,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(width),
      );

  @override
  bool get confirmsTrashItself => true;

  @override
  String get trashExplanation =>
      'Android keeps trashed photos for about 30 days before removing them '
      'for good.';

  @override
  Duration? get trashKeepsFor => const Duration(days: 30);

  // Uses Android's own trash (MediaStore.createTrashRequest). Android shows
  // one prompt for the whole batch and answers with every id if the user
  // agrees, or none if they cancel.
  @override
  Future<List<TrashedPhoto>> moveToTrash(
    List<Photo> photos, {
    void Function(int done, int total)? onProgress,
  }) async {
    // Save a small copy of each photo first. Once a photo is in the trash,
    // Android hides it even from this app, so the Recently deleted screen
    // would have nothing to show. Eight at a time: Android makes thumbnails
    // on background threads, so asking for several at once is much faster.
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

    final assets = [for (final photo in photos) _assets[photo.id]!];
    final moved = (await PhotoManager.editor.android.moveToTrash(assets))
        .toSet();

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
          ),
        );
      } else if (thumbnail != null) {
        // Not trashed after all (the user cancelled), so drop the copy.
        await File(thumbnail).delete();
      }
    }
    return trashed;
  }

  @override
  Future<Set<String>> restoreFromTrash(List<TrashedPhoto> photos) async {
    // A trashed photo can't be looked up, but Android only needs its id and
    // media type (1 means image) to find it again.
    final assets = [
      for (final photo in photos)
        AssetEntity(id: photo.photoId, typeInt: 1, width: 0, height: 0),
    ];
    final restored = (await PhotoManager.editor.android.restoreFromTrash(
      assets,
    )).toSet();
    await forgetTrashed([
      for (final photo in photos)
        if (restored.contains(photo.photoId)) photo,
    ]);
    return restored;
  }

  @override
  Future<void> forgetTrashed(List<TrashedPhoto> photos) async {
    for (final photo in photos) {
      if (photo.thumbnailPath case final path?) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  // Writes a 320 px copy of [photo] and returns its path, or null if Android
  // couldn't make one.
  Future<String?> _saveThumbnail(Photo photo) async {
    final bytes = await _assets[photo.id]!.thumbnailDataWithSize(
      const ThumbnailSize.square(320),
      quality: 80,
    );
    if (bytes == null) return null;
    final file = File(p.join(thumbnailFolder.path, '${photo.id}.jpg'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Wraps photo_manager's object in ours, keeping it to find again by id.
  Photo _toPhoto(AssetEntity asset) {
    _assets[asset.id] = asset;
    return Photo(
      id: asset.id,
      name: asset.title ?? 'Photo',
      date: asset.createDateTime,
    );
  }
}
