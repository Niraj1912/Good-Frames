import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_swipe/data/folder_photo_repository.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/trashed_photo.dart';

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
    return (await repository.photosIn(all).first)
        .map((photo) => photo.name)
        .toList();
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
    final photos = await repository.photosIn(all).first;
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
    final photos = await repository.photosIn(camera).first;

    expect(photos.map((photo) => photo.name), ['IMG_0002.JPG', 'IMG_0001.jpg']);
  });

  test('says how many HEIC files it had to skip', () async {
    expect(repository.notice, isNull); // Nothing scanned yet.

    await repository.albums();

    expect(repository.notice, contains('1 photo in HEIC format'));
  });

  test('sees files added since the last scan when reloaded', () async {
    await repository.albums();
    await File(p.join(root.path, 'Camera', 'new.jpg')).writeAsBytes([1]);

    final albums = await repository.albums();

    expect(albums.first.photoCount, 6);
  });

  test('finds nothing when the folder does not exist', () async {
    final missing = FolderPhotoRepository(
      rootPath: p.join(root.path, 'missing'),
    );

    expect(await missing.albums(), isEmpty);
  });

  group('moveToTrash', () {
    String inRoot(String path) => p.joinAll([root.path, ...path.split('/')]);

    Future<Photo> photoAt(String path) async {
      final all = await repository
          .photosIn((await repository.albums()).first)
          .first;
      return all.firstWhere((photo) => photo.id == inRoot(path));
    }

    test('moves photos into the trash folder, keeping their folders', () async {
      final camera = await photoAt('Camera/IMG_0001.jpg');
      final screenshot = await photoAt('Screenshots/IMG_0001.jpg');

      final moved = await repository.moveToTrash([camera, screenshot]);

      expect(moved.map((photo) => photo.photoId), [camera.id, screenshot.id]);
      expect(
        moved.first.trashPath,
        inRoot('_SwipeSort_Trash/Camera/IMG_0001.jpg'),
      );
      expect(File(camera.id).existsSync(), isFalse);
      expect(
        File(inRoot('_SwipeSort_Trash/Camera/IMG_0001.jpg')).existsSync(),
        isTrue,
      );
      expect(
        File(inRoot('_SwipeSort_Trash/Screenshots/IMG_0001.jpg')).existsSync(),
        isTrue,
      );
      expect(await allPhotoNames(), isNot(contains('IMG_0001.jpg')));
    });

    test('never overwrites a photo already in the trash', () async {
      final earlier = File(inRoot('_SwipeSort_Trash/Camera/IMG_0001.jpg'));
      await earlier.parent.create(recursive: true);
      await earlier.writeAsString('deleted last week');

      await repository.moveToTrash([await photoAt('Camera/IMG_0001.jpg')]);

      expect(await earlier.readAsString(), 'deleted last week');
      expect(
        File(inRoot('_SwipeSort_Trash/Camera/IMG_0001 (2).jpg')).existsSync(),
        isTrue,
      );
    });

    test('refuses to move a file outside its folder', () async {
      final elsewhere = await Directory.systemTemp.createTemp('elsewhere_');
      addTearDown(() => elsewhere.delete(recursive: true));
      final outside = File(p.join(elsewhere.path, 'important.jpg'));
      await outside.writeAsBytes([1, 2, 3]);

      final moved = await repository.moveToTrash([
        Photo(id: outside.path, name: 'important.jpg', date: DateTime(2026)),
      ]);

      expect(moved, isEmpty);
      expect(outside.existsSync(), isTrue);
    });

    test('reports a photo that has already gone as not moved', () async {
      final photo = await photoAt('loose.jpg');
      await File(photo.id).delete();

      expect(await repository.moveToTrash([photo]), isEmpty);
    });

    test('restoring puts a photo back where it was', () async {
      final photo = await photoAt('Camera/IMG_0001.jpg');
      final trashed = await repository.moveToTrash([photo]);

      final restored = await repository.restoreFromTrash(trashed);

      expect(restored, {photo.id});
      expect(File(photo.id).existsSync(), isTrue);
      expect(File(trashed.single.trashPath!).existsSync(), isFalse);
      expect(await allPhotoNames(), contains('IMG_0001.jpg'));
    });

    test('restoring never overwrites a new file with the old name', () async {
      final photo = await photoAt('Camera/IMG_0001.jpg');
      final trashed = await repository.moveToTrash([photo]);
      await File(photo.id).writeAsString('a newer photo');

      await repository.restoreFromTrash(trashed);

      expect(await File(photo.id).readAsString(), 'a newer photo');
      expect(File(inRoot('Camera/IMG_0001 (2).jpg')).existsSync(), isTrue);
    });

    test('restoring only takes files from its own trash folder', () async {
      final elsewhere = await Directory.systemTemp.createTemp('elsewhere_');
      addTearDown(() => elsewhere.delete(recursive: true));
      final outside = File(p.join(elsewhere.path, 'important.jpg'));
      await outside.writeAsBytes([1, 2, 3]);

      final restored = await repository.restoreFromTrash([
        TrashedPhoto(
          photoId: inRoot('Camera/stolen.jpg'),
          name: 'stolen.jpg',
          trashedAt: DateTime(2026),
          trashPath: outside.path,
        ),
      ]);

      expect(restored, isEmpty);
      expect(outside.existsSync(), isTrue);
    });

    test(
      'a photo already removed from the trash folder is not restored',
      () async {
        final trashed = await repository.moveToTrash([
          await photoAt('loose.jpg'),
        ]);
        await File(trashed.single.trashPath!).delete(); // The user emptied it.

        expect(await repository.restoreFromTrash(trashed), isEmpty);
      },
    );

    test('deleting forever erases the file in the trash folder', () async {
      final photo = await photoAt('Camera/IMG_0001.jpg');
      final trashed = await repository.moveToTrash([photo]);

      final deleted = await repository.deleteForever(trashed);

      expect(deleted, {photo.id});
      expect(File(trashed.single.trashPath!).existsSync(), isFalse);
      expect(File(photo.id).existsSync(), isFalse);
      // Everything else is untouched.
      expect(File(inRoot('Camera/IMG_0002.JPG')).existsSync(), isTrue);
    });

    // The most important rule: whatever the database says, it never erases a
    // photo that's still in the library, or a file outside the photo folder.
    test(
      'deleting forever only ever erases files in its trash folder',
      () async {
        final elsewhere = await Directory.systemTemp.createTemp('elsewhere_');
        addTearDown(() => elsewhere.delete(recursive: true));
        final outside = File(p.join(elsewhere.path, 'important.jpg'));
        await outside.writeAsBytes([1, 2, 3]);
        final inLibrary = inRoot('Camera/IMG_0002.JPG');

        final deleted = await repository.deleteForever([
          TrashedPhoto(
            photoId: inLibrary,
            name: 'IMG_0002.JPG',
            trashedAt: DateTime(2026),
            trashPath: inLibrary, // Points at the library, not the trash.
          ),
          TrashedPhoto(
            photoId: inRoot('Camera/other.jpg'),
            name: 'other.jpg',
            trashedAt: DateTime(2026),
            trashPath: outside.path,
          ),
          TrashedPhoto(
            photoId: inRoot('Camera/no_path.jpg'),
            name: 'no_path.jpg',
            trashedAt: DateTime(2026),
          ),
        ]);

        expect(deleted, isEmpty);
        expect(File(inLibrary).existsSync(), isTrue);
        expect(outside.existsSync(), isTrue);
      },
    );

    test(
      'a photo already gone from the trash folder counts as deleted',
      () async {
        final photo = await photoAt('loose.jpg');
        final trashed = await repository.moveToTrash([photo]);
        await File(trashed.single.trashPath!).delete(); // The user emptied it.

        expect(await repository.deleteForever(trashed), {photo.id});
      },
    );
  });
}
