import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/data/android_media.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/chosen_folder.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/widgets/formatting.dart';

/// Photos from folders the user picked with Android's folder picker, for
/// people who'd rather not share their whole gallery. No photo permission
/// is involved: picking a folder is the permission, and it covers only that
/// folder and the folders inside it.
///
/// Photos are identified by their MediaStore id, as in
/// [AndroidPhotoRepository], so decisions and the trash carry over between
/// the two.
class AndroidFolderPhotoRepository
    with AndroidTrash
    implements ChosenFoldersRepository {
  AndroidFolderPhotoRepository({required this.thumbnailFolder});

  @override
  final Directory thumbnailFolder;

  static const _allPhotosId = '';

  // From the last scan: each album's photos, newest first.
  var _albumPhotos = <String, List<FoundPhoto>>{};

  // MediaStore ids looked up so far, by document id. Null means Android
  // hasn't indexed the file, so it can't be trashed, and it's left out.
  final _mediaIds = <String, String?>{};

  // Where each photo is, by MediaStore id.
  final _uris = <String, String>{};

  // Folders that couldn't be opened in the last scan.
  String? _unreadableNotice;

  @override
  String get sourceName => 'the folders you chose';

  // Says so when photos are missing, rather than albums quietly showing
  // fewer than they hold.
  @override
  String? get notice {
    final unindexed = _mediaIds.values.where((id) => id == null).length;
    final lines = [
      ?_unreadableNotice,
      if (unindexed > 0)
        "${photoCount(unindexed)} can't be sorted yet, because Android "
            "hasn't added ${unindexed == 1 ? 'it' : 'them'} to its gallery.",
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  @override
  Future<List<ChosenFolder>> chosenFolders() => AndroidMedia.chosenFolders();

  @override
  Future<ChosenFolder?> chooseFolder() => AndroidMedia.pickFolder();

  @override
  Future<void> forgetFolder(ChosenFolder folder) =>
      AndroidMedia.forgetFolder(folder);

  // Nothing to ask: access comes from picking folders.
  @override
  Future<AccessStatus> requestAccess() => checkAccess();

  @override
  Future<AccessStatus> checkAccess() async => (await chosenFolders()).isEmpty
      ? AccessStatus.denied
      : AccessStatus.granted;

  // There's no settings page for this kind of access: picking folders is
  // how it's given.
  @override
  Future<void> openAccessSettings() async {
    await chooseFolder();
  }

  @override
  Future<void> changeSelectedPhotos() async {
    await chooseFolder();
  }

  @override
  Future<List<Album>> albums() async {
    // A photo inside two chosen folders (DCIM, and DCIM/Camera too) counts
    // once.
    final found = <String, FoundPhoto>{};
    final unreadable = <String>[];
    for (final folder in await chosenFolders()) {
      try {
        for (final photo in await AndroidMedia.scanFolder(folder)) {
          found.putIfAbsent(photo.documentId, () => photo);
        }
      } on PlatformException {
        unreadable.add(folder.name); // Moved or deleted since it was chosen.
      }
    }
    _unreadableNotice = unreadable.isEmpty
        ? null
        : "Couldn't open ${unreadable.join(', ')}. It may have been moved or "
              'deleted; remove it under Folders.';

    final all = found.values.toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final byFolder = <String, List<FoundPhoto>>{};
    for (final photo in all) {
      (byFolder[photo.folderId] ??= []).add(photo);
    }
    final folderIds = byFolder.keys.toList()
      ..sort(
        (a, b) => byFolder[a]!.first.folderName.toLowerCase().compareTo(
          byFolder[b]!.first.folderName.toLowerCase(),
        ),
      );
    // "All photos" only when there's more than one album to combine.
    final order = [if (byFolder.length > 1) _allPhotosId, ...folderIds];
    _albumPhotos = {if (byFolder.length > 1) _allPhotosId: all, ...byFolder};

    // Each album's cover is its newest photo, which needs its id.
    await _lookUp([for (final id in order) _albumPhotos[id]!.first]);
    return [
      for (final id in order)
        Album(
          id: id,
          name: id == _allPhotosId
              ? 'All photos'
              : _albumPhotos[id]!.first.folderName,
          photoCount: _albumPhotos[id]!.length,
          cover: _toPhoto(_albumPhotos[id]!.first),
        ),
    ];
  }

  // Looking up ids takes a moment per photo, so they come in pages, like
  // the gallery's: a small first one, so sorting can start almost at once,
  // then bigger ones in the background.
  @override
  Stream<List<Photo>> photosIn(Album album) async* {
    final photos = _albumPhotos[album.id] ?? const <FoundPhoto>[];
    var start = 0;
    var pageSize = 200;
    while (start < photos.length) {
      final end = min(start + pageSize, photos.length);
      final page = photos.sublist(start, end);
      await _lookUp(page);
      // `?` leaves out photos Android hasn't indexed.
      yield [for (final found in page) ?_toPhoto(found)];
      start = end;
      pageSize = 1000;
    }
  }

  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      SharedPhotoImage(_uris[photo.id]!, maxWidth: width, maxHeight: width * 2);

  @override
  ImageProvider detailImageFor(Photo photo, {int maxSize = 4096}) =>
      SharedPhotoImage(
        _uris[photo.id]!,
        maxWidth: maxSize,
        maxHeight: maxSize,
        quality: 92,
      );

  @override
  Future<List<int>?> trashThumbnail(Photo photo) => AndroidMedia.image(
    _uris[photo.id]!,
    maxWidth: 320,
    maxHeight: 320,
    quality: 80,
  );

  // Asks Android for the MediaStore ids of [photos] not looked up yet.
  Future<void> _lookUp(List<FoundPhoto> photos) async {
    final missing = [
      for (final photo in photos)
        if (!_mediaIds.containsKey(photo.documentId)) photo,
    ];
    final ids = await AndroidMedia.mediaIds([
      for (final photo in missing) photo.uri,
    ]);
    for (final (index, photo) in missing.indexed) {
      final id = index < ids.length ? ids[index] : null;
      _mediaIds[photo.documentId] = id;
      if (id != null) _uris[id] = photo.uri;
    }
  }

  Photo? _toPhoto(FoundPhoto found) {
    final id = _mediaIds[found.documentId];
    if (id == null) return null;
    return Photo(
      id: id,
      name: found.name,
      date: found.modified,
      sizeBytes: found.sizeBytes,
    );
  }
}
