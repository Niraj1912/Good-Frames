import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_swipe/data/android_media.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/photo_order.dart';

/// Reads the phone's whole gallery through Android's MediaStore, using the
/// photo_manager plugin. The trash goes through the app's own Android code
/// ([AndroidTrash]), shared with folder mode.
class AndroidPhotoRepository with AndroidTrash implements PhotoRepository {
  AndroidPhotoRepository({required this.thumbnailFolder});

  @override
  final Directory thumbnailFolder;

  // photo_manager's own objects, kept so they can be found again by id.
  final _albums = <String, AssetPathEntity>{};
  final _assets = <String, AssetEntity>{};

  static const _photosOnly = PermissionRequestOption(
    // Photos only. Asking for videos too would need more permissions.
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  // The orders to ask Android for. Without one, Android returns photos in
  // the order they joined its database, which is roughly oldest first.
  // Photos copied in together share the same second, so the id breaks
  // ties: paging needs an order that never changes between pages, or a
  // photo could be skipped or repeated.
  static final _newestFirst = _byDateAdded(newestFirst: true);
  static final _oldestFirst = _byDateAdded(newestFirst: false);

  static CustomFilter _byDateAdded({required bool newestFirst}) =>
      CustomFilter.sql(
        where: '',
        orderBy: [
          OrderByItem.named(
            column: CustomColumns.base.createDate,
            isAsc: !newestFirst,
          ),
          OrderByItem.named(column: CustomColumns.base.id, isAsc: !newestFirst),
        ],
      );

  @override
  String get sourceName => "your phone's gallery";

  @override
  String? get notice => null;

  @override
  Future<AccessStatus> requestAccess() async => _toStatus(
    await PhotoManager.requestPermissionExtend(requestOption: _photosOnly),
  );

  @override
  Future<AccessStatus> checkAccess() async => _toStatus(
    await PhotoManager.getPermissionState(requestOption: _photosOnly),
  );

  static AccessStatus _toStatus(PermissionState state) => switch (state) {
    PermissionState.authorized => AccessStatus.granted,
    PermissionState.limited => AccessStatus.limited,
    _ => AccessStatus.denied,
  };

  @override
  Future<void> openAccessSettings() => PhotoManager.openSetting();

  // Shows Android 14's system photo picker so the user can share more photos.
  @override
  Future<void> changeSelectedPhotos() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<List<Album>> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: _newestFirst,
    );
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
  Stream<List<Photo>> photosIn(
    Album album, {
    PhotoOrder order = PhotoOrder.newestFirst,
  }) async* {
    // Android does the ordering, so each page arrives already in order. The
    // albums were listed newest first.
    final path = switch (order) {
      PhotoOrder.newestFirst => _albums[album.id]!,
      PhotoOrder.oldestFirst => _albums[album.id]!.copyWith(
        filterOption: _oldestFirst,
      ),
    };
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

  // A very large thumbnail rather than the original file: Android decodes
  // it (HEIC included), applies the rotation, and caps the size, so a
  // 50-megapixel photo can't exhaust memory. It asks for the photo's own
  // size: asking for more would make Android scale small photos *up*.
  @override
  ImageProvider detailImageFor(Photo photo, {int maxSize = 4096}) {
    final asset = _assets[photo.id]!;
    final width = asset.orientatedWidth;
    final height = asset.orientatedHeight;
    final ThumbnailSize size;
    if (width <= 0 || height <= 0) {
      size = const ThumbnailSize.square(2048); // Size unknown: a safe guess.
    } else {
      final shrink = min(1.0, maxSize / max(width, height));
      size = ThumbnailSize((width * shrink).round(), (height * shrink).round());
    }
    return AssetEntityImageProvider(
      asset,
      isOriginal: false,
      thumbnailSize: size,
    );
  }

  // The small copy kept for the Recently deleted screen, made by Android.
  @override
  Future<List<int>?> trashThumbnail(Photo photo) => _assets[photo.id]!
      .thumbnailDataWithSize(const ThumbnailSize.square(320), quality: 80);

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
