import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/state/sort_controller.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

void main() {
  const camera = Album(id: 'Camera', name: 'Camera', photoCount: 3);
  late DecisionStore store;

  setUp(() async => store = await openTestStore());
  tearDown(() => store.close());

  Future<SortController> openCamera({DecisionStore? using}) async {
    final controller = SortController(
      repository: FakePhotoRepository(photoCounts: {'Camera': 3}),
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

  test('each decision moves on to the next photo and is counted', () async {
    final controller = await openCamera();

    await controller.decide(Decision.keep);
    await controller.decide(Decision.delete);

    expect(controller.current?.name, 'IMG_3.jpg');
    expect(controller.keepCount, 1);
    expect(controller.deleteCount, 1);
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
  Future<void> remove(String photoId) async => throw Exception('disk full');

  @override
  Future<void> removeAll(Iterable<String> photoIds) async =>
      throw Exception('disk full');

  @override
  Future<void> close() async {}
}
