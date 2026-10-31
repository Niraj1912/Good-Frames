import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';

/// Reads the phone's gallery through Android's MediaStore, using the
/// photo_manager plugin.
class AndroidPhotoRepository implements PhotoRepository {
  // photo_manager's own objects, kept so they can be found again by id.
  final _albums = <String, AssetPathEntity>{};
  final _assets = <String, AssetEntity>{};

  @override
  String get sourceName => "your phone's gallery";

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
      albums.add(
        Album(
          id: path.id,
          name: path.isAll ? 'All photos' : path.name,
          photoCount: count,
        ),
      );
    }
    return albums;
  }

  // Loads the whole album at once. Fine for now; Phase 5 checks how this
  // behaves with 10,000 photos.
  @override
  Future<List<Photo>> photosIn(Album album) async {
    final path = _albums[album.id]!;
    final count = await path.assetCountAsync;
    final assets = await path.getAssetListRange(start: 0, end: count);
    return [
      for (final asset in assets)
        Photo(
          id: _remember(asset),
          name: asset.title ?? 'Photo',
          date: asset.createDateTime,
        ),
    ];
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

  String _remember(AssetEntity asset) {
    _assets[asset.id] = asset;
    return asset.id;
  }
}
