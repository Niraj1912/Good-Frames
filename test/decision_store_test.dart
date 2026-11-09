import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/fingerprint.dart';
import 'package:good_frames/models/trashed_photo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_store.dart';

void main() {
  late DecisionStore store;

  setUp(() async => store = await openTestStore());
  tearDown(() => store.close());

  test('starts empty', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('saves decisions, oldest first', () async {
    await store.record('a', Decision.keep);
    await store.record('b', Decision.delete);

    final records = await store.loadAll();
    expect(records.map((record) => record.photoId), ['a', 'b']);
    expect(records.map((record) => record.decision), [
      Decision.keep,
      Decision.delete,
    ]);
  });

  test('a new decision for a photo replaces the old one', () async {
    await store.record('a', Decision.keep);
    await store.record('b', Decision.keep);
    await store.record('a', Decision.delete);

    final records = await store.loadAll();
    expect(records.map((record) => record.photoId), ['b', 'a']);
    expect(records.last.decision, Decision.delete);
  });

  test('update changes a decision without moving it in the order', () async {
    await store.record('a', Decision.delete);
    await store.record('b', Decision.keep);

    await store.update('a', Decision.keep);

    final records = await store.loadAll();
    expect(records.map((record) => record.photoId), ['a', 'b']);
    expect(records.first.decision, Decision.keep);
  });

  test('can forget one decision or several', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await store.record(id, Decision.keep);
    }

    await store.remove('a');
    await store.removeAll(['b', 'c']);

    expect((await store.loadAll()).map((record) => record.photoId), ['d']);
  });

  test('decisions survive closing and reopening the database', () async {
    final folder = await Directory.systemTemp.createTemp('goodframes_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    final first = await DecisionStore.open(databaseFactoryFfiNoIsolate, path);
    await first.record('a', Decision.keep);
    await first.close();

    final second = await DecisionStore.open(databaseFactoryFfiNoIsolate, path);
    addTearDown(second.close);
    expect((await second.loadAll()).single.photoId, 'a');
  });

  group('trash list', () {
    TrashedPhoto trashed(String id, int day) => TrashedPhoto(
      photoId: id,
      name: '$id.jpg',
      trashedAt: DateTime(2026, 11, day),
      thumbnailPath: 'thumbs/$id.jpg',
      sizeBytes: 1000,
    );

    test('remembers trashed photos and forgets their decisions', () async {
      await store.record('a', Decision.delete);
      await store.record('b', Decision.keep);

      await store.recordTrashed([trashed('a', 1)]);

      expect((await store.loadAll()).map((record) => record.photoId), ['b']);
      final list = await store.loadTrashed();
      expect(list.single.photoId, 'a');
      expect(list.single.thumbnailPath, 'thumbs/a.jpg');
      expect(list.single.trashedAt, DateTime(2026, 11, 1));
    });

    test('lists the newest first and can forget some', () async {
      await store.recordTrashed([trashed('a', 1), trashed('b', 3)]);
      await store.recordTrashed([trashed('c', 2)]);

      expect((await store.loadTrashed()).map((photo) => photo.photoId), [
        'b',
        'c',
        'a',
      ]);

      await store.forgetTrashed(['b', 'a']);
      expect((await store.loadTrashed()).single.photoId, 'c');
    });
  });

  test('upgrades a version 1 database without losing decisions', () async {
    final folder = await Directory.systemTemp.createTemp('goodframes_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    // A database exactly as the Phase 2 app left it: decisions only.
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE decisions (
              photo_id TEXT PRIMARY KEY,
              decision TEXT NOT NULL,
              decided_at INTEGER NOT NULL
            )
          ''');
          await db.insert('decisions', {
            'photo_id': 'a',
            'decision': 'keep',
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

    expect((await upgraded.loadAll()).single.photoId, 'a');
    // The newer tables exist.
    expect(await upgraded.loadTrashed(), isEmpty);
    expect(await upgraded.loadSettings(), isEmpty);
  });

  test('upgrades a version 2 database without losing anything', () async {
    final folder = await Directory.systemTemp.createTemp('goodframes_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    // As release 1.0.0 left it: decisions and the trash, no settings.
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE decisions (
              photo_id   TEXT PRIMARY KEY,
              decision   TEXT NOT NULL CHECK (decision IN ('keep', 'delete')),
              decided_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE trash (
              photo_id       TEXT PRIMARY KEY,
              name           TEXT NOT NULL,
              trashed_at     INTEGER NOT NULL,
              thumbnail_path TEXT,
              trash_path     TEXT,
              size_bytes     INTEGER
            )
          ''');
          await db.insert('decisions', {
            'photo_id': 'a',
            'decision': 'delete',
            'decided_at': 1,
          });
          await db.insert('trash', {
            'photo_id': 'b',
            'name': 'IMG_2.jpg',
            'trashed_at': 2,
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
    expect((await upgraded.loadTrashed()).single.name, 'IMG_2.jpg');
    await upgraded.saveSetting('theme', 'dark');
    expect(await upgraded.loadSettings(), {'theme': 'dark'});
  });

  test('upgrades a version 3 database without losing anything', () async {
    final folder = await Directory.systemTemp.createTemp('goodframes_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    // As release 1.0.1 left it: decisions, the trash and settings.
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE decisions (
              photo_id   TEXT PRIMARY KEY,
              decision   TEXT NOT NULL CHECK (decision IN ('keep', 'delete')),
              decided_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE trash (
              photo_id       TEXT PRIMARY KEY,
              name           TEXT NOT NULL,
              trashed_at     INTEGER NOT NULL,
              thumbnail_path TEXT,
              trash_path     TEXT,
              size_bytes     INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.insert('decisions', {
            'photo_id': 'a',
            'decision': 'keep',
            'decided_at': 1,
          });
          await db.insert('settings', {'key': 'theme', 'value': 'dark'});
        },
      ),
    );
    await old.close();

    final upgraded = await DecisionStore.open(
      databaseFactoryFfiNoIsolate,
      path,
    );
    addTearDown(upgraded.close);

    expect((await upgraded.loadAll()).single.decision, Decision.keep);
    expect(await upgraded.loadSettings(), {'theme': 'dark'});
    // The new table is there, and empty.
    expect(await upgraded.loadFingerprints(), isEmpty);
  });

  test('upgrades a version 4 database, starting the fingerprints afresh', () async {
    final folder = await Directory.systemTemp.createTemp('goodframes_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    // Version 4 was never released: it had fingerprints without a colour.
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE decisions (photo_id TEXT PRIMARY KEY, '
            "decision TEXT NOT NULL CHECK (decision IN ('keep', 'delete')), "
            'decided_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE trash (photo_id TEXT PRIMARY KEY, name TEXT NOT NULL, '
            'trashed_at INTEGER NOT NULL, thumbnail_path TEXT, trash_path TEXT, '
            'size_bytes INTEGER)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE fingerprints (photo_id TEXT PRIMARY KEY, '
            'stamp INTEGER NOT NULL, hash INTEGER NOT NULL, '
            'sharpness REAL NOT NULL)',
          );
          await db.insert('decisions', {
            'photo_id': 'a',
            'decision': 'keep',
            'decided_at': 1,
          });
          await db.insert('fingerprints', {
            'photo_id': 'a',
            'stamp': 1,
            'hash': 1,
            'sharpness': 0.1,
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

    // What the user decided is kept; the cache starts empty and works.
    expect((await upgraded.loadAll()).single.decision, Decision.keep);
    expect(await upgraded.loadFingerprints(), isEmpty);
    await upgraded.saveFingerprints([
      const SavedFingerprint('a', 2, Fingerprint(2, 0.2, 0x102030)),
    ]);
    expect(
      (await upgraded.loadFingerprints())['a']!.fingerprint.colour,
      0x102030,
    );
  });

  group('fingerprints', () {
    test('are saved and loaded back exactly', () async {
      // A hash with the top bit set is negative: it has to survive the trip.
      const hash = -0x1234567890ABCDEF;
      await store.saveFingerprints([
        const SavedFingerprint('a', 100, Fingerprint(hash, 0.125, 0xC8140A)),
        const SavedFingerprint('b', 200, Fingerprint(7, 0.5)),
      ]);

      final loaded = await store.loadFingerprints();
      expect(loaded.keys, {'a', 'b'});
      expect(
        loaded['a']!.fingerprint,
        const Fingerprint(hash, 0.125, 0xC8140A),
      );
      expect(loaded['a']!.stamp, 100);
      expect(loaded['b']!.fingerprint.hash, 7);
    });

    test('saved again for the same photo, they replace the old one', () async {
      await store.saveFingerprints([
        const SavedFingerprint('a', 1, Fingerprint(1, 0.1)),
      ]);
      await store.saveFingerprints([
        const SavedFingerprint('a', 2, Fingerprint(2, 0.2)),
      ]);

      final loaded = await store.loadFingerprints();
      expect(loaded, hasLength(1));
      expect(loaded['a']!.stamp, 2);
      expect(loaded['a']!.fingerprint.hash, 2);
    });

    test('are not touched by forgetting decisions', () async {
      await store.saveFingerprints([
        const SavedFingerprint('a', 1, Fingerprint(1, 0.1)),
      ]);
      await store.record('a', Decision.keep);
      await store.removeAll(['a']);

      expect(await store.loadFingerprints(), isNotEmpty);
    });
  });

  test('a setting saved again replaces the old value', () async {
    await store.saveSetting('order', 'oldestFirst');
    await store.saveSetting('order', 'newestFirst');

    expect(await store.loadSettings(), {'order': 'newestFirst'});
  });
}
