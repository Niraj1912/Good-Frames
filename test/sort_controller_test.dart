import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/trashed_photo.dart';
import 'package:photo_swipe/state/sort_controller.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

void main() {
  const camera = Album(id: 'Camera', name: 'Camera', photoCount: 3);
  late DecisionStore store;

  setUp(() async => store = await openTestStore());
  tearDown(() => store.close());

  Future<SortController> openCamera({
    DecisionStore? using,
    FakePhotoRepository? repository,
  }) async {
    final controller = SortController(
      repository: repository ?? FakePhotoRepository(photoCounts: {'Camera': 3}),
      store: using ?? store,
      album: camera,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test('starts at the first photo with nothing sorted', () async {
    final controller = await openCamera();

    expect(controller.current?.name, 'IMG_1.jpg');
    expect(controller.total, 3);
    expect(controller.sortedCount, 0);
    expect(controller.canUndo, isFalse);
  });

  test('shows each page as it arrives, before the rest has loaded', () async {
    final repository = FakePhotoRepository(photoCounts: {'Camera': 3})
      ..pageSize = 1;
    final controller = SortController(
      repository: repository,
      store: store,
      album: camera,
    );
    addTearDown(controller.dispose);
    final seen = <(int, bool)>[];
    controller.addListener(
      () => seen.add((controller.loadedCount, controller.isFullyLoaded)),
    );

    await controller.load();

    expect(seen, [(1, false), (2, false), (3, false), (3, true)]);
  });

  test('is not done while later pages are still loading', () async {
    await store.record('Camera/1', Decision.keep); // Sorted last time.
    final repository = FakePhotoRepository(photoCounts: {'Camera': 2})
      ..pageSize = 1;
    final controller = SortController(
      repository: repository,
      store: store,
      album: camera,
    );
    addTearDown(controller.dispose);
    bool? doneAfterFirstPage;
    controller.addListener(() {
      if (controller.loadedCount == 1 && !controller.isFullyLoaded) {
        doneAfterFirstPage = controller.isDone;
      }
    });

    await controller.load();

    expect(doneAfterFirstPage, isFalse);
    expect(controller.current?.name, 'IMG_2.jpg');
  });

  test('counts only this album, even with decisions from others', () async {
    await store.record('Screenshots/1', Decision.delete);
    final controller = await openCamera();

    expect(controller.sortedCount, 0);
    expect(controller.deleteCount, 0);
    expect(controller.canUndo, isFalse);
  });

  test('each decision moves on to the next photo and is counted', () async {
    final controller = await openCamera();

    await controller.decide(Decision.keep);
    await controller.decide(Decision.delete);

    expect(controller.current?.name, 'IMG_3.jpg');
    expect(controller.keepCount, 1);
    expect(controller.deleteCount, 1);
  });

  test('lists the photos waiting after the current one', () async {
    final controller = await openCamera();
    expect(controller.upcoming(5).map((photo) => photo.name), [
      'IMG_2.jpg',
      'IMG_3.jpg',
    ]);

    await controller.decide(Decision.keep);
    expect(controller.upcoming(5).map((photo) => photo.name), ['IMG_3.jpg']);
  });

  test('undo brings back the photos in reverse order', () async {
    final controller = await openCamera();
    await controller.decide(Decision.keep);
    await controller.decide(Decision.delete);

    await controller.undo();
    expect(controller.current?.name, 'IMG_2.jpg');
    expect(controller.sortedCount, 1);

    await controller.undo();
    expect(controller.current?.name, 'IMG_1.jpg');
    expect(controller.canUndo, isFalse);
  });

  test('is done once every photo is sorted', () async {
    final controller = await openCamera();

    for (var i = 0; i < 3; i++) {
      await controller.decide(Decision.keep);
    }

    expect(controller.isDone, isTrue);
    expect(controller.current, isNull);
  });

  test('picks up where it left off when opened again', () async {
    final first = await openCamera();
    await first.decide(Decision.keep);
    await first.decide(Decision.delete);

    // A new controller with the same database, like reopening the app.
    final second = await openCamera();
    expect(second.current?.name, 'IMG_3.jpg');
    expect(second.sortedCount, 2);

    // Undo history survives too.
    await second.undo();
    expect(second.current?.name, 'IMG_2.jpg');
  });

  test('start over forgets every decision in the album', () async {
    final controller = await openCamera();
    await controller.decide(Decision.keep);
    await controller.decide(Decision.delete);

    await controller.startOver();

    expect(controller.sortedCount, 0);
    expect(controller.current?.name, 'IMG_1.jpg');
    expect(await store.loadAll(), isEmpty);
  });

  group('review and trash', () {
    late FakePhotoRepository repository;
    late SortController controller;

    // Marks IMG_1 delete, IMG_2 keep, IMG_3 delete.
    setUp(() async {
      repository = FakePhotoRepository(photoCounts: {'Camera': 3});
      controller = await openCamera(repository: repository);
      await controller.decide(Decision.delete);
      await controller.decide(Decision.keep);
      await controller.decide(Decision.delete);
    });

    List<String> names(List<Photo> photos) =>
        photos.map((photo) => photo.name).toList();

    test('lists the photos marked for deletion', () {
      expect(names(controller.markedForDelete), ['IMG_1.jpg', 'IMG_3.jpg']);
    });

    test('rescuing a photo is saved and keeps the undo order', () async {
      await controller.changeDecision(
        controller.markedForDelete.first,
        Decision.keep,
      );
      expect(names(controller.markedForDelete), ['IMG_3.jpg']);
      expect(controller.keepCount, 2);

      // Reopened: still rescued, and undo still takes back IMG_3 first.
      final reopened = await openCamera(repository: repository);
      expect(names(reopened.markedForDelete), ['IMG_3.jpg']);
      await reopened.undo();
      expect(reopened.current?.name, 'IMG_3.jpg');
    });

    test('trashing removes the photos and forgets their decisions', () async {
      final result = await controller.trashMarked();

      expect(result.moved, 2);
      expect(result.cancelled, isFalse);
      expect(result.freedBytes, 1000 + 3000);
      expect(repository.trashed, ['Camera/1', 'Camera/3']);
      expect(controller.total, 1);
      expect(controller.markedForDelete, isEmpty);
      expect(controller.isDone, isTrue);
      expect((await store.loadAll()).map((record) => record.photoId), [
        'Camera/2',
      ]);
      // Listed for the Recently deleted screen.
      expect(
        (await store.loadTrashed()).map((photo) => photo.photoId),
        unorderedEquals(['Camera/1', 'Camera/3']),
      );
    });

    test('if the user cancels, nothing changes', () async {
      repository.cancelTrash = true;

      final result = await controller.trashMarked();

      expect(result.cancelled, isTrue);
      expect(controller.total, 3);
      expect(names(controller.markedForDelete), ['IMG_1.jpg', 'IMG_3.jpg']);
      expect(await store.loadAll(), hasLength(3));
    });

    test('photos deleted by another app stop being tracked', () async {
      repository.vanish('Camera/3'); // Deleted elsewhere while marked.

      final result = await controller.trashMarked();

      expect(result.moved, 1);
      expect(result.vanished, 1);
      expect(controller.markedForDelete, isEmpty);
      expect(controller.total, 1);
      expect((await store.loadAll()).map((record) => record.photoId), [
        'Camera/2',
      ]);
    });

    test('photos that could not be moved stay marked', () async {
      repository.lockedIds = {'Camera/3'};

      final result = await controller.trashMarked();

      expect(result.moved, 1);
      expect(result.requested, 2);
      expect(names(controller.markedForDelete), ['IMG_3.jpg']);
    });
  });

  test('a decision that fails to save is taken back', () async {
    final controller = await openCamera(using: _BrokenStore());

    await expectLater(controller.decide(Decision.keep), throwsException);

    expect(controller.current?.name, 'IMG_1.jpg');
    expect(controller.sortedCount, 0);
    expect(controller.canUndo, isFalse);
  });
}

/// A store whose disk is "full": loading works, saving always fails.
class _BrokenStore implements DecisionStore {
  @override
  Future<List<DecisionRecord>> loadAll() async => [];

  @override
  Future<void> record(String photoId, Decision decision) async =>
      throw Exception('disk full');

  @override
  Future<void> update(String photoId, Decision decision) async =>
      throw Exception('disk full');

  @override
  Future<void> remove(String photoId) async => throw Exception('disk full');

  @override
  Future<void> removeAll(Iterable<String> photoIds) async =>
      throw Exception('disk full');

  @override
  Future<void> recordTrashed(List<TrashedPhoto> photos) async =>
      throw Exception('disk full');

  @override
  Future<List<TrashedPhoto>> loadTrashed() async => [];

  @override
  Future<void> forgetTrashed(Iterable<String> photoIds) async =>
      throw Exception('disk full');

  @override
  Future<void> close() async {}
}
