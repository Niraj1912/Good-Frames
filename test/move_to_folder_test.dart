import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/main.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/target_folder.dart';
import 'package:good_frames/state/settings.dart';
import 'package:good_frames/state/sort_controller.dart';
import 'package:good_frames/widgets/swipe_card.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/broken_store.dart';
import 'support/test_store.dart';

void main() {
  const camera = Album(id: 'Camera', name: 'Camera', photoCount: 3);
  late DecisionStore store;
  late FakePhotoRepository repository;

  setUp(() async {
    store = await openTestStore();
    repository = FakePhotoRepository(photoCounts: {'Camera': 3})
      ..canMove = true;
  });
  tearDown(() => store.close());

  Future<SortController> open({DecisionStore? using}) async {
    final controller = SortController(
      repository: repository,
      store: using ?? store,
      album: camera,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  group('folder names', () {
    test('are tidied up', () {
      expect(cleanFolderName('  Trip   to Goa '), 'Trip to Goa');
    });

    test('cannot reach outside Pictures or hide', () {
      for (final bad in [
        '',
        '   ',
        '..',
        '.hidden',
        'a/b',
        r'a\b',
        '../x',
        'what?',
        'a:b',
        'a' * 65,
      ]) {
        expect(cleanFolderName(bad), isNull, reason: bad);
      }
    });
  });

  group('filing a photo', () {
    test('counts as a Keep and is queued for its folder', () async {
      final controller = await open();
      final photo = controller.current!;

      await controller.decide(Decision.keep, folder: 'Goa');

      expect(controller.decisionFor(photo), Decision.keep);
      expect(controller.keepCount, 1);
      expect(controller.filedCount, 1);
      expect(controller.folderFor(photo), 'Goa');
      expect(controller.lastWasFiled, isTrue);
    });

    test('is remembered after the app is closed', () async {
      var controller = await open();
      final photo = controller.current!;
      await controller.decide(Decision.keep, folder: 'Goa');

      controller = await open();

      expect(controller.folderFor(photo), 'Goa');
      expect(controller.decisionFor(photo), Decision.keep);
    });

    test('undo takes back both the Keep and the filing', () async {
      final controller = await open();
      final photo = controller.current!;
      await controller.decide(Decision.keep, folder: 'Goa');

      await controller.undo();

      expect(controller.current, photo);
      expect(controller.filedCount, 0);
      expect(await store.loadPendingMoves(), isEmpty);
      expect(await store.loadAll(), isEmpty);
    });

    test('a plain Keep or Delete is never queued', () async {
      final controller = await open();
      await controller.decide(Decision.keep);
      await controller.decide(Decision.delete, folder: 'Goa');

      expect(controller.filedCount, 0);
      expect(await store.loadPendingMoves(), isEmpty);
    });

    test('if saving fails, nothing is left queued', () async {
      final controller = await open(using: BrokenStore());
      final photo = controller.current!;

      await expectLater(
        controller.decide(Decision.keep, folder: 'Goa'),
        throwsException,
      );

      expect(controller.folderFor(photo), isNull);
      expect(controller.decisionFor(photo), isNull);
      expect(controller.current, photo);
    });

    test('start over forgets the queue too', () async {
      final controller = await open();
      await controller.decide(Decision.keep, folder: 'Goa');

      await controller.startOver();

      expect(controller.filedCount, 0);
      expect(await store.loadPendingMoves(), isEmpty);
    });

    test('leaving a photo where it is keeps the Keep', () async {
      final controller = await open();
      final photo = controller.current!;
      await controller.decide(Decision.keep, folder: 'Goa');

      await controller.unfile(photo);

      expect(controller.filedCount, 0);
      expect(controller.decisionFor(photo), Decision.keep);
      expect(await store.loadPendingMoves(), isEmpty);

      await controller.refile(photo, 'Goa');
      expect(controller.folderFor(photo), 'Goa');
    });
  });

  group('moving the queue', () {
    test('moves each photo into its own folder, once', () async {
      final controller = await open();
      final first = controller.current!;
      await controller.decide(Decision.keep, folder: 'Goa');
      final second = controller.current!;
      await controller.decide(Decision.keep, folder: 'Family');

      final result = await controller.moveFiled();

      expect(result.moved, 2);
      expect(result.failed, 0);
      expect(result.folders, {'Goa', 'Family'});
      expect(repository.movedTo, {first.id: 'Goa', second.id: 'Family'});
      expect(controller.filedCount, 0);
      // Still Keeps, and nothing is left to move.
      expect(controller.decisionFor(first), Decision.keep);
      expect(await store.loadPendingMoves(), isEmpty);
    });

    test('a photo that cannot move stays queued to try again', () async {
      final controller = await open();
      final stuck = controller.current!;
      await controller.decide(Decision.keep, folder: 'Goa');
      await controller.decide(Decision.keep, folder: 'Goa');
      repository.unmovableIds = {stuck.id};

      final result = await controller.moveFiled();

      expect(result.moved, 1);
      expect(result.failed, 1);
      expect(controller.folderFor(stuck), 'Goa');
      expect(await store.loadPendingMoves(), {stuck.id: 'Goa'});
    });

    test('saying no moves nothing and keeps the queue', () async {
      final controller = await open();
      await controller.decide(Decision.keep, folder: 'Goa');
      repository.cancelMove = true;

      final result = await controller.moveFiled();

      expect(result.cancelled, isTrue);
      expect(controller.filedCount, 1);
      expect(repository.movedTo, isEmpty);
    });

    test('with nothing queued, nothing happens', () async {
      final controller = await open();

      final result = await controller.moveFiled();

      expect(result.requested, 0);
    });
  });

  group('the database', () {
    test('upgrades from version 5 without losing decisions', () async {
      final folder = await Directory.systemTemp.createTemp('goodframes_db_');
      addTearDown(() => folder.delete(recursive: true));
      final path = p.join(folder.path, 'decisions.db');

      final old = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE decisions (photo_id TEXT PRIMARY KEY, '
              "decision TEXT NOT NULL CHECK (decision IN ('keep', 'delete')), "
              'decided_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE trash (photo_id TEXT PRIMARY KEY, name TEXT NOT '
              'NULL, trashed_at INTEGER NOT NULL, thumbnail_path TEXT, '
              'trash_path TEXT, size_bytes INTEGER)',
            );
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT '
              'NULL)',
            );
            await db.execute(
              'CREATE TABLE fingerprints (photo_id TEXT PRIMARY KEY, stamp '
              'INTEGER NOT NULL, hash INTEGER NOT NULL, sharpness REAL NOT '
              'NULL, colour INTEGER NOT NULL)',
            );
            await db.insert('decisions', {
              'photo_id': 'a',
              'decision': 'delete',
              'decided_at': 1,
            });
          },
        ),
      );
      await old.close();

      final upgraded = await DecisionStore.open(
        databaseFactoryFfiNoIsolate,
        path,
      );
      addTearDown(upgraded.close);

      expect((await upgraded.loadAll()).single.decision, Decision.delete);
      expect(await upgraded.loadPendingMoves(), isEmpty);
      await upgraded.recordFiled('b', 'Goa');
      expect(await upgraded.loadPendingMoves(), {'b': 'Goa'});
    });

    test('trashing a photo clears a queued move', () async {
      await store.recordFiled('a', 'Goa');
      await store.removeAll(['a']);
      expect(await store.loadPendingMoves(), isEmpty);
    });
  });

  group('settings', () {
    test('remember the folder and the recent ones', () async {
      final settings = await Settings.load(store);
      expect(settings.targetFolder, isNull);

      await settings.setTargetFolder('Goa');
      await settings.setTargetFolder('Family');
      await settings.setTargetFolder('Goa');

      final again = await Settings.load(store);
      expect(again.targetFolder, 'Goa');
      expect(again.recentFolders, ['Goa', 'Family']);
    });
  });

  group('swiping down', () {
    testWidgets('files a photo, then moving happens from Review', (
      tester,
    ) async {
      final settings = await Settings.load(store);
      await tester.pumpWidget(
        GoodFramesApp(repository: repository, store: store, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      // No folder yet, so swiping down asks for one first.
      await tester.drag(find.byType(SwipeCard), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Swipe down into…'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Trip to Goa');
      await tester.tap(find.text('Use this folder'));
      await tester.pumpAndSettle();

      expect(settings.targetFolder, 'Trip to Goa');
      expect(find.text('Down → Trip to Goa'), findsOneWidget);

      // The next swipe down goes straight to the folder.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('Swipe down into…'), findsNothing);

      await tester.tap(find.byTooltip('Review photos to delete or move'));
      await tester.pumpAndSettle();
      expect(find.text('Move 2 photos into Trip to Goa'), findsOneWidget);

      await tester.tap(find.text('Move 2 photos into Trip to Goa'));
      await tester.pumpAndSettle();

      expect(repository.movedTo.values.toSet(), {'Trip to Goa'});
      expect(repository.movedTo, hasLength(2));
    });

    testWidgets('closing the folder sheet brings the photo back', (
      tester,
    ) async {
      final settings = await Settings.load(store);
      await tester.pumpWidget(
        GoodFramesApp(repository: repository, store: store, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(SwipeCard), const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // Outside the sheet.
      await tester.pumpAndSettle();

      expect(find.text('0 / 3 sorted'), findsOneWidget);
    });

    testWidgets('does nothing where moving is not possible', (tester) async {
      repository.canMove = false;
      final settings = await Settings.load(store);
      await tester.pumpWidget(
        GoodFramesApp(repository: repository, store: store, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(SwipeCard), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.text('Swipe down into…'), findsNothing);
      expect(find.text('0 / 3 sorted'), findsOneWidget);
    });
  });
}
