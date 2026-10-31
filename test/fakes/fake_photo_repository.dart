import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';

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
  Future<List<Photo>> photosIn(Album album) async => _photos[album.id]!;

  @override
  ImageProvider imageFor(Photo photo, {required int width}) =>
      MemoryImage(_onePixelPng);
}

// The smallest valid PNG: a single pixel.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
