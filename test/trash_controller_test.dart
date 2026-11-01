import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/state/sort_controller.dart';
import 'package:photo_swipe/state/trash_controller.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

void main() {
  late DecisionStore store;
  late FakePhotoRepository repository;

  setUp(() async {
    store = await openTestStore();
    repository = FakePhotoRepository(photoCounts: {'Camera': 3});
  });
  tearDown(() => store.close());

  // Trashes IMG_1 and IMG_3 the normal way, through the sort controller.
  Future<void> trashTwo() async {
    final sorter = SortController(
      repository: repository,
      store: store,
      album: const Album(id: 'Camera', name: 'Camera', photoCount: 3),
    );
    addTearDown(sorter.dispose);
    await sorter.load();
    await sorter.decide(Decision.delete);
    await sorter.decide(Decision.keep);
    await sorter.decide(Decision.delete);
    await sorter.trashMarked();
  }

  Future<TrashController> openTrash({DateTime? now}) async {
    final controller = TrashController(
      repository: repository,
      store: store,
      now: now == null ? null : () => now,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test('lists the photos the app moved to the trash', () async {
    await trashTwo();

    final trash = await openTrash();

    expect(
      trash.photos.map((photo) => photo.name),
      unorderedEquals(['IMG_1.jpg', 'IMG_3.jpg']),
    );
  });

  test('restoring brings photos back and takes them off the list', () async {
    await trashTwo();
    final trash = await openTrash();
    final img1 = trash.photos.firstWhere((photo) => photo.name == 'IMG_1.jpg');

    expect(await trash.restore([img1]), 1);

    expect(trash.photos.map((photo) => photo.name), ['IMG_3.jpg']);
    expect((await store.loadTrashed()).single.name, 'IMG_3.jpg');
    final camera = await repository.allPhotosIn(
      const Album(id: 'Camera', name: 'Camera', photoCount: 3),
    );
    expect(camera.map((photo) => photo.name), ['IMG_1.jpg', 'IMG_2.jpg']);
  });

  test('if the user cancels, everything stays in the trash', () async {
    await trashTwo();
    final trash = await openTrash();
    repository.cancelRestore = true;

    expect(await trash.restore(trash.photos), 0);

    expect(trash.photos, hasLength(2));
    expect(await store.loadTrashed(), hasLength(2));
  });

  test('deleting forever erases photos and takes them off the list', () async {
    await trashTwo();
    final trash = await openTrash();
    final img1 = trash.photos.firstWhere((photo) => photo.name == 'IMG_1.jpg');

    expect(await trash.deleteForever([img1]), 1);

    expect(repository.erased, ['Camera/1']);
    expect(trash.photos.map((photo) => photo.name), ['IMG_3.jpg']);
    expect((await store.loadTrashed()).single.name, 'IMG_3.jpg');
    // Gone for good: restoring it now finds nothing.
    expect(await trash.restore([img1]), 0);
  });

  test('if the user cancels deleting forever, nothing is erased', () async {
    await trashTwo();
    final trash = await openTrash();
    repository.cancelDeleteForever = true;

    expect(await trash.deleteForever(trash.photos), 0);

    expect(repository.erased, isEmpty);
    expect(trash.photos, hasLength(2));
    expect(await store.loadTrashed(), hasLength(2));
  });

  test('stops listing photos the system has removed for good', () async {
    repository.trashKeepsFor = const Duration(days: 30);
    await trashTwo();

    // A month and a day later.
    final trash = await openTrash(
      now: DateTime.now().add(const Duration(days: 31)),
    );

    expect(trash.photos, isEmpty);
    expect(await store.loadTrashed(), isEmpty);
    expect(repository.forgotten, hasLength(2)); // Thumbnails freed.
  });

  test('shows how long each photo has left', () async {
    repository.trashKeepsFor = const Duration(days: 30);
    await trashTwo();

    final trash = await openTrash(
      now: DateTime.now().add(const Duration(days: 10)),
    );

    expect(trash.timeLeft(trash.photos.first)!.inDays, 19);
  });
}
