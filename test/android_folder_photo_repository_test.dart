import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/data/android_folder_photo_repository.dart';
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/trashed_photo.dart';

// Folder mode's Dart side, against a stand-in for the app's Android code:
// the platform channels answer from the tables below instead of a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const foldersChannel = MethodChannel('goodframes/folders');
  const trashChannel = MethodChannel('goodframes/trash');

  Map<String, Object?> photo(
    String uri,
    String folder, {
    required int modified,
    String? id,
  }) => {
    'uri': uri,
    'id': id ?? uri,
    'name': uri.split('/').last,
    'size': 1000,
    'modified': modified,
    'folderId': 'primary:DCIM/$folder',
    'folderName': folder,
  };

  // The user shared DCIM, and also DCIM/Camera inside it.
  final scans = {
    'tree:dcim': [
      photo('dcim/Camera/a.jpg', 'Camera', modified: 3000, id: 'a'),
      photo('dcim/Camera/b.jpg', 'Camera', modified: 2000, id: 'b'),
      photo('dcim/Screenshots/s.png', 'Screenshots', modified: 1000),
      photo('dcim/Screenshots/new.png', 'Screenshots', modified: 500),
    ],
    // The same Camera photo again, reached through the other shared folder.
    'tree:camera': [photo('camera/a.jpg', 'Camera', modified: 3000, id: 'a')],
  };
  // Android's ids. new.png hasn't been indexed yet, so it has none.
  final mediaIds = {
    'dcim/Camera/a.jpg': '11',
    'camera/a.jpg': '11',
    'dcim/Camera/b.jpg': '12',
    'dcim/Screenshots/s.png': '13',
  };

  late List<Map<String, Object?>> shared;
  late List<MethodCall> trashCalls;
  late bool userSaysNo;
  late Set<String> unreadable;
  late Directory thumbnails;
  late AndroidFolderPhotoRepository repository;

  setUp(() async {
    shared = [
      {'uri': 'tree:dcim', 'name': 'DCIM', 'path': 'DCIM'},
      {'uri': 'tree:camera', 'name': 'Camera', 'path': 'DCIM/Camera'},
    ];
    trashCalls = [];
    userSaysNo = false;
    unreadable = {};
    thumbnails = await Directory.systemTemp.createTemp('thumbnails_');
    repository = AndroidFolderPhotoRepository(thumbnailFolder: thumbnails);

    messenger.setMockMethodCallHandler(foldersChannel, (call) async {
      final args = call.arguments as Map<Object?, Object?>?;
      switch (call.method) {
        case 'list':
          return shared;
        case 'scan':
          final uri = args!['uri']! as String;
          if (unreadable.contains(uri)) {
            throw PlatformException(code: 'failed', message: 'gone');
          }
          return scans[uri];
        case 'mediaIds':
          return [for (final uri in args!['uris']! as List) mediaIds[uri]];
        case 'image':
          return Uint8List.fromList([1, 2, 3]);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(trashChannel, (call) async {
      trashCalls.add(call);
      return userSaysNo ? <String>[] : (call.arguments as Map)['ids'];
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(foldersChannel, null);
    messenger.setMockMethodCallHandler(trashChannel, null);
    await thumbnails.delete(recursive: true);
  });

  Future<Album> album(String name) async =>
      (await repository.albums()).firstWhere((album) => album.name == name);

  test('makes one album per folder, after "All photos"', () async {
    final albums = await repository.albums();

    expect(albums.map((album) => album.name), [
      'All photos',
      'Camera',
      'Screenshots',
    ]);
    // a.jpg is in both shared folders but counts once.
    expect(albums.map((album) => album.photoCount), [4, 2, 2]);
    // Covers are each album's newest photo, with Android's id.
    expect(albums.map((album) => album.cover?.id), ['11', '11', '13']);
  });

  test('photos have Android ids; ones not indexed yet are left out', () async {
    final screenshots = await album('Screenshots');

    final photos = await repository.photosIn(screenshots).toList();

    expect(photos.expand((page) => page).map((photo) => photo.id), ['13']);
    // And the album list says so, rather than quietly showing fewer.
    expect(repository.notice, contains("1 photo can't be sorted yet"));
  });

  test('photos come newest first', () async {
    final photos = await repository.photosIn(await album('All photos')).first;

    expect(photos.map((photo) => photo.name), ['a.jpg', 'b.jpg', 's.png']);
  });

  test('trashing asks Android by id and keeps a small copy of each', () async {
    final camera = await repository.photosIn(await album('Camera')).first;

    final trashed = await repository.moveToTrash(camera);

    expect(trashCalls.single.method, 'trash');
    expect((trashCalls.single.arguments as Map)['ids'], ['11', '12']);
    expect(trashed.map((photo) => photo.photoId), ['11', '12']);
    for (final photo in trashed) {
      expect(File(photo.thumbnailPath!).existsSync(), isTrue);
    }
  });

  test('if the user says no, nothing is trashed and no copies stay', () async {
    final camera = await repository.photosIn(await album('Camera')).first;
    userSaysNo = true;

    expect(await repository.moveToTrash(camera), isEmpty);
    expect(thumbnails.listSync(), isEmpty);
  });

  test(
    'restoring and deleting forever ask Android, then free the copies',
    () async {
      final camera = await repository.photosIn(await album('Camera')).first;
      final trashed = await repository.moveToTrash(camera);

      expect(await repository.restoreFromTrash([trashed.first]), {'11'});
      expect(await repository.deleteForever([trashed.last]), {'12'});

      expect(trashCalls.map((call) => call.method), [
        'trash',
        'restore',
        'deleteForever',
      ]);
      expect(thumbnails.listSync(), isEmpty);
    },
  );

  test('access is granted only once a folder is shared', () async {
    expect(await repository.checkAccess(), AccessStatus.granted);
    shared = [];
    expect(await repository.checkAccess(), AccessStatus.denied);
    expect(await repository.albums(), isEmpty);
  });

  test(
    'a folder that can no longer be opened is skipped, with a notice',
    () async {
      unreadable.add('tree:camera');

      final albums = await repository.albums();

      expect(albums, isNotEmpty); // DCIM still works.
      expect(repository.notice, contains("Couldn't open Camera"));
    },
  );

  test('nothing trashed with an empty list never bothers Android', () async {
    expect(await repository.restoreFromTrash(const <TrashedPhoto>[]), isEmpty);
    expect(trashCalls, isEmpty);
  });
}
