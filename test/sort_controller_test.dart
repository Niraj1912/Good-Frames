import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/photo_order.dart';
import 'package:good_frames/state/sort_controller.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/broken_store.dart';
import 'support/test_store.dart';

void main() {
  const camera = Album(id: 'Camera', name: 'Camera', photoCount: 3);
  // Four photos 20 days apart: IMG_1 in December 2025, IMG_2 and IMG_3 in
  // November, IMG_4 in October.
  final december = DateTime(2025, 12);
  final november = DateTime(2025, 11);
  final october = DateTime(2025, 10);
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

  Future<SortController> openMonths({
    PhotoOrder order = PhotoOrder.newestFirst,
  }) async {
    final controller = SortController(
      repository: FakePhotoRepository(
        photoCounts: {'Camera': 4},
        spacing: const Duration(days: 20),
      ),
      store: store,
      album: camera,
      order: order,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  Iterable<String> names(Iterable<Photo> photos) =>
      photos.map((photo) => photo.name);

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
    final controller = await openCamera(using: BrokenStore());

    await expectLater(controller.decide(Decision.keep), throwsException);

    expect(controller.current?.name, 'IMG_1.jpg');
    expect(controller.sortedCount, 0);
    expect(controller.canUndo, isFalse);
  });

  group('one month at a time', () {
    test('lists each month with its photos, newest first', () async {
      final controller = await openMonths();
      await controller.decide(Decision.keep); // IMG_1, December

      expect(controller.months, [
        (month: december, photos: 1, sorted: 1),
        (month: november, photos: 2, sorted: 0),
        (month: october, photos: 1, sorted: 0),
      ]);
    });

    test('oldest first lists the oldest month first', () async {
      final controller = await openMonths(order: PhotoOrder.oldestFirst);
      expect(controller.months.map((month) => month.month), [
        october,
        november,
        december,
      ]);
    });

    test('a month shows and counts only its own photos', () async {
      final controller = await openMonths();

      controller.showMonth(november);
      expect(controller.current?.name, 'IMG_2.jpg');
      expect(names(controller.upcoming(5)), ['IMG_3.jpg']);
      expect(controller.total, 2);

      await controller.decide(Decision.delete);
      expect(controller.sortedCount, 1);
      expect(controller.deleteCount, 1);
      expect(names(controller.markedForDelete), ['IMG_2.jpg']);
    });

    test('decisions count in the whole album too', () async {
      final controller = await openMonths();
      controller.showMonth(november);
      await controller.decide(Decision.keep);

      controller.showMonth(null);
      expect(controller.sortedCount, 1);
      expect(controller.total, 4);
      expect(controller.current?.name, 'IMG_1.jpg');
    });

    test('when a month is done, the next one still to sort is next', () async {
      final controller = await openMonths();
      controller.showMonth(december);

      await controller.decide(Decision.keep);
      expect(controller.isDone, isTrue);
      expect(controller.nextMonth, november);

      // Skipping ahead to October: nothing after it, so back to the top,
      // where December is done and November isn't.
      controller.showMonth(october);
      await controller.decide(Decision.keep);
      expect(controller.nextMonth, november);

      // Every month done: nothing next.
      controller.showMonth(november);
      await controller.decide(Decision.keep);
      await controller.decide(Decision.keep);
      expect(controller.isDone, isTrue);
      expect(controller.nextMonth, isNull);
    });

    test('undo only takes back decisions in the month shown', () async {
      final controller = await openMonths();
      await controller.decide(Decision.keep); // IMG_1, December

      controller.showMonth(november);
      expect(controller.canUndo, isFalse);
      await controller.decide(Decision.keep); // IMG_2
      await controller.undo();
      expect(controller.current?.name, 'IMG_2.jpg');

      controller.showMonth(null);
      expect(controller.sortedCount, 1); // December's decision is still there.
    });

    test('start over in a month forgets only that month', () async {
      final controller = await openMonths();
      await controller.decide(Decision.keep); // IMG_1, December
      await controller.decide(Decision.delete); // IMG_2, November

      controller.showMonth(november);
      await controller.startOver();
      expect(controller.sortedCount, 0);

      controller.showMonth(null);
      expect(controller.sortedCount, 1);
      expect(controller.keepCount, 1);
    });

    test('a month emptied by the trash goes back to every month', () async {
      final controller = await openMonths();
      controller.showMonth(december);
      await controller.decide(Decision.delete); // Its only photo.

      await controller.trashMarked();
      expect(controller.month, isNull);
      expect(controller.current?.name, 'IMG_2.jpg');
    });
  });

  group('deciding a group together', () {
    test('every photo in it is decided in one go', () async {
      final controller = await openCamera();

      await controller.decideMany({
        'Camera/1': Decision.keep,
        'Camera/2': Decision.delete,
      });

      expect(controller.keepCount, 1);
      expect(controller.deleteCount, 1);
      expect(controller.current?.name, 'IMG_3.jpg');
      // Saved too: another visit to the album finds them decided.
      final again = await openCamera();
      expect(again.sortedCount, 2);
    });

    test('one undo takes back the whole group', () async {
      final controller = await openCamera();
      await controller.decide(Decision.keep); // IMG_1, on its own.
      await controller.decideMany({
        'Camera/2': Decision.keep,
        'Camera/3': Decision.delete,
      });
      expect(controller.sortedCount, 3);

      await controller.undo();

      expect(controller.sortedCount, 1); // Only IMG_1 is left decided.
      expect(controller.current?.name, 'IMG_2.jpg');
      expect(controller.lastDecision, Decision.keep); // The earlier one.
      // And it's forgotten for good, not just on screen.
      final again = await openCamera();
      expect(again.sortedCount, 1);
    });

    test('a group is not a single decision for the slide-in', () async {
      final controller = await openCamera();
      await controller.decideMany({
        'Camera/1': Decision.keep,
        'Camera/2': Decision.delete,
      });

      expect(controller.canUndo, isTrue);
      expect(controller.lastDecision, isNull);
    });

    test('photos already decided, or not in the album, are left out', () async {
      final controller = await openCamera();
      await controller.decide(Decision.keep); // IMG_1.

      await controller.decideMany({
        'Camera/1': Decision.delete, // Already kept: not changed.
        'Camera/2': Decision.delete,
        'Elsewhere/9': Decision.delete, // Not here at all.
      });

      expect(controller.keepCount, 1);
      expect(controller.deleteCount, 1);
      expect(
        controller.decisionFor(controller.markedForDelete.single)?.name,
        'delete',
      );
    });

    test('a group that cannot be saved is taken back', () async {
      final controller = await openCamera(using: BrokenStore());
      controller.putOff(); // IMG_1 is put off, so it can come back too.

      await expectLater(
        controller.decideMany({
          'Camera/1': Decision.keep,
          'Camera/2': Decision.delete,
        }),
        throwsException,
      );

      expect(controller.sortedCount, 0);
      expect(controller.canUndo, isTrue); // Only the putting off.
      expect(controller.laterCount, 1); // IMG_1 is still waiting for later.
    });

    test('a group is taken out of the later line', () async {
      final controller = await openCamera();
      controller.putOff(); // IMG_1.
      expect(controller.laterCount, 1);

      await controller.decideMany({'Camera/1': Decision.keep});

      expect(controller.laterCount, 0);
    });

    test('only the month shown can be decided', () async {
      final controller = await openMonths();
      controller.showMonth(november); // IMG_2 and IMG_3.

      await controller.decideMany({
        'Camera/1': Decision.keep, // December: not in this month.
        'Camera/2': Decision.keep,
      });

      controller.showMonth(null);
      expect(controller.sortedCount, 1);
      expect(controller.decisionFor(controller.unsortedPhotos.first), isNull);
    });

    test('lists the photos with no decision yet, in album order', () async {
      final controller = await openCamera();
      await controller.decide(Decision.keep); // IMG_1.

      expect(names(controller.unsortedPhotos), ['IMG_2.jpg', 'IMG_3.jpg']);

      controller.putOff(); // IMG_2 is put off but still unsorted.
      expect(names(controller.unsortedPhotos), ['IMG_2.jpg', 'IMG_3.jpg']);
    });
  });

  group('decide later', () {
    test('a photo put off comes back once the rest are sorted', () async {
      final controller = await openCamera();

      controller.putOff();
      expect(controller.current?.name, 'IMG_2.jpg');
      expect(controller.laterCount, 1);
      expect(controller.sortedCount, 0); // Not a decision.
      expect(controller.upcoming(5).map((photo) => photo.name), [
        'IMG_3.jpg',
        'IMG_1.jpg', // Last in line.
      ]);

      await controller.decide(Decision.keep);
      await controller.decide(Decision.keep);
      expect(controller.current?.name, 'IMG_1.jpg');
      expect(controller.laterCount, 0); // It's back.
      expect(controller.isDone, isFalse);

      await controller.decide(Decision.delete);
      expect(controller.isDone, isTrue);
    });

    test('they come back in the order they were put off', () async {
      final controller = await openCamera();

      controller.putOff(); // 1
      controller.putOff(); // 2
      await controller.decide(Decision.keep); // 3
      expect(controller.current?.name, 'IMG_1.jpg');

      controller.putOff(); // 1 again: now behind 2.
      expect(controller.current?.name, 'IMG_2.jpg');
      expect(controller.upcoming(5).map((photo) => photo.name), ['IMG_1.jpg']);
    });

    test('undo brings a photo put off straight back', () async {
      final controller = await openCamera();
      await controller.decide(Decision.keep); // 1

      controller.putOff(); // 2
      expect(controller.lastWasPutOff, isTrue);
      expect(controller.lastDecision, isNull);

      await controller.undo();
      expect(controller.current?.name, 'IMG_2.jpg');
      expect(controller.laterCount, 0);
      // Then the decision before it.
      expect(controller.lastWasPutOff, isFalse);
      expect(controller.lastDecision, Decision.keep);
    });

    test('is not saved: the album opens with it in its usual place', () async {
      final controller = await openCamera();
      controller.putOff();

      final reopened = await openCamera();
      expect(reopened.current?.name, 'IMG_1.jpg');
      expect(reopened.laterCount, 0);
    });

    test(
      'waits for every page, so it never jumps ahead of new photos',
      () async {
        final repository = FakePhotoRepository(photoCounts: {'Camera': 3})
          ..pageSize = 1;
        final controller = SortController(
          repository: repository,
          store: store,
          album: camera,
        );
        addTearDown(controller.dispose);
        // Put off the only photo loaded so far, the moment it arrives.
        var putOff = false;
        Photo? next;
        controller.addListener(() {
          if (controller.loadedCount == 1 && !putOff) {
            putOff = true;
            controller.putOff();
            next = controller.current;
          }
        });

        await controller.load();

        expect(putOff, isTrue);
        expect(next, isNull); // It waited for the next page...
        expect(controller.current?.name, 'IMG_2.jpg'); // ...which came first.
      },
    );

    test('a photo put off in a month comes back in that month', () async {
      final controller = await openMonths();
      controller.showMonth(november);

      controller.putOff(); // IMG_2
      expect(controller.current?.name, 'IMG_3.jpg');
      await controller.decide(Decision.keep);
      expect(controller.current?.name, 'IMG_2.jpg');
    });

    test('start over forgets photos put off too', () async {
      final controller = await openCamera();
      controller.putOff();

      await controller.startOver();
      expect(controller.current?.name, 'IMG_1.jpg');
      expect(controller.laterCount, 0);
      expect(controller.canUndo, isFalse);
    });
  });
}
