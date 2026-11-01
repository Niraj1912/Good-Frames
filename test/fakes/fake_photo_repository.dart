import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/trashed_photo.dart';

/// In-memory photos for tests: fast, predictable, and needs no files or
/// phone. Tests change [access] to play the part of the user.
class FakePhotoRepository implements PhotoRepository {
  FakePhotoRepository({
    this.access = AccessStatus.granted,
    Map<String, int> photoCounts = const {'Camera': 3},
  }) : _photos = {
         for (final MapEntry(key: album, value: count) in photoCounts.entries)
           album: [
             for (var i = 1; i <= count; i++)
               Photo(
                 id: '$album/$i',
                 name: 'IMG_$i.jpg',
                 date: DateTime(2026, 1, i),
                 sizeBytes: 1000 * i,
               ),
           ],
       };

  /// What [requestAccess] answers.
  AccessStatus access;
  bool settingsOpened = false;
  bool selectionChanged = false;
  final Map<String, List<Photo>> _photos;

  /// Plays the user tapping Cancel on the system's trash prompt.
  bool cancelTrash = false;

  /// Photos that refuse to move, like files open in another program.
  Set<String> lockedIds = {};

  /// Ids moved to the trash so far, in order.
  final trashed = <String>[];

  /// Plays the user tapping Cancel on the system's restore prompt.
  bool cancelRestore = false;

  /// Ids whose leftovers were freed by [forgetTrashed].
  final forgotten = <String>[];

  @override
  Duration? trashKeepsFor;

  @override
  String? notice;

  // Trashed photos and the album they came from, so they can come back.
  final _inTrash = <String, (String, Photo)>{};

  @override
  String get sourceName => 'the fake gallery';

  @override
  Future<AccessStatus> requestAccess() async => access;

  @override
  Future<void> openAccessSettings() async {
    settingsOpened = true;
  }

  @override
  Future<void> changeSelectedPhotos() async {
    selectionChanged = true;
  }

  @override
  Future<List<Album>> albums() async => [
    for (final MapEntry(key: name, value: photos) in _photos.entries)
      if (photos.isNotEmpty)
        Album(id: name, name: name, photoCount: photos.length),
  ];

  @override
  // Copies, like a real source returns: callers must never share our list.
  Stream<List<Photo>> photosIn(Album album) async* {
    final photos = [..._photos[album.id]!];
    for (var start = 0; start < photos.length; start += pageSize) {
      yield photos.skip(start).take(pageSize).toList();
    }
  }

  /// Photos per page from [photosIn]. Lower it to test loading in pages.
  int pageSize = 1 << 30;

  /// Every photo in [album], all pages joined.
  Future<List<Photo>> allPhotosIn(Album album) =>
      photosIn(album).expand((page) => page).toList();

  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      MemoryImage(_onePixelPng);

  // No system prompt here, so the app shows its own, which tests can tap.
  @override
  bool get confirmsTrashItself => false;

  @override
  String get trashExplanation => 'They go to the fake trash.';

  @override
  Future<List<TrashedPhoto>> moveToTrash(
    List<Photo> photos, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (cancelTrash) return [];
    final moved = <TrashedPhoto>[];
    for (final (index, photo) in photos.indexed) {
      onProgress?.call(index + 1, photos.length);
      if (lockedIds.contains(photo.id)) continue;
      var found = false;
      for (final MapEntry(key: album, value: list) in _photos.entries) {
        if (list.remove(photo)) {
          _inTrash[photo.id] = (album, photo);
          found = true;
        }
      }
      if (!found) continue; // Already gone: nothing to move.
      trashed.add(photo.id);
      moved.add(
        TrashedPhoto(
          photoId: photo.id,
          name: photo.name,
          trashedAt: DateTime.now(),
          sizeBytes: photo.sizeBytes,
        ),
      );
    }
    return moved;
  }

  /// Plays another app deleting [photoId] behind SwipeSort's back.
  void vanish(String photoId) {
    for (final list in _photos.values) {
      list.removeWhere((photo) => photo.id == photoId);
    }
  }

  @override
  Future<Set<String>> restoreFromTrash(List<TrashedPhoto> photos) async {
    if (cancelRestore) return {};
    final restored = <String>{};
    for (final trashedPhoto in photos) {
      final entry = _inTrash.remove(trashedPhoto.photoId);
      if (entry == null) continue;
      final (album, photo) = entry;
      _photos[album]!
        ..add(photo)
        ..sort((a, b) => a.date.compareTo(b.date));
      restored.add(photo.id);
    }
    return restored;
  }

  @override
  Future<void> forgetTrashed(List<TrashedPhoto> photos) async {
    forgotten.addAll(photos.map((photo) => photo.photoId));
  }
}

// The smallest valid PNG: a single pixel.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
