import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_swipe/data/folder_photo_repository.dart';

void main() {
  late Directory root;
  late FolderPhotoRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('swipesort_test_');
    repository = FolderPhotoRepository(rootPath: root.path);
    for (final path in [
      'loose.jpg',
      'Camera/IMG_0001.jpg',
      'Camera/IMG_0002.JPG',
      'Screenshots/IMG_0001.jpg',
      'WhatsApp Images/chat.webp',
      // None of these should show up:
      'notes.txt',
      'Thumbs.db',
      'Camera/photo.heic',
      'Camera/.hidden.jpg',
      '_SwipeSort_Trash/deleted.jpg',
    ]) {
      final file = File(p.join(root.path, path));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
    }
  });

  tearDown(() => root.delete(recursive: true));

  Future<List<String>> allPhotoNames() async {
    final all = (await repository.albums()).first;
    return (await repository.photosIn(all)).map((photo) => photo.name).toList();
  }

  test('makes one album per folder, after "All photos"', () async {
    final albums = await repository.albums();

    expect(albums.map((album) => album.name), [
      'All photos',
      p.basename(root.path),
      'Camera',
      'Screenshots',
      'WhatsApp Images',
    ]);
    expect(albums.map((album) => album.photoCount), [5, 1, 2, 1, 1]);
  });

  test('skips unsupported, hidden and trashed files', () async {
    expect(
      await allPhotoNames(),
      unorderedEquals([
        'loose.jpg',
        'IMG_0001.jpg',
        'IMG_0002.JPG',
        'IMG_0001.jpg',
        'chat.webp',
      ]),
    );
  });

  test('keeps same-named photos in different folders apart', () async {
    final all = (await repository.albums()).first;
    final photos = await repository.photosIn(all);
    final ids = photos
        .where((photo) => photo.name == 'IMG_0001.jpg')
        .map((photo) => photo.id)
        .toSet();

    expect(ids, hasLength(2));
  });

  test('sorts newest first', () async {
    await File(p.join(root.path, 'Camera', 'IMG_0001.jpg'))
        .setLastModified(DateTime(2020));
    await File(p.join(root.path, 'Camera', 'IMG_0002.JPG'))
        .setLastModified(DateTime(2025));

    final camera = (await repository.albums()).firstWhere(
      (album) => album.name == 'Camera',
    );
    final photos = await repository.photosIn(camera);

    expect(photos.map((photo) => photo.name), ['IMG_0002.JPG', 'IMG_0001.jpg']);
  });

  test('finds nothing when the folder does not exist', () async {
    final missing = FolderPhotoRepository(
      rootPath: p.join(root.path, 'missing'),
    );

    expect(await missing.albums(), isEmpty);
  });
}
