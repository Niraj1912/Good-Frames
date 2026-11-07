import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/fingerprint.dart';
import 'package:photo_swipe/models/trashed_photo.dart';
import 'package:sqflite/sqflite.dart';

/// One saved decision.
class DecisionRecord {
  const DecisionRecord(this.photoId, this.decision);

  final String photoId;
  final Decision decision;
}

/// Saves keep/delete decisions, the list of photos moved to the trash, and
/// the user's settings in a SQLite database, so they survive the app being
/// closed or killed. Nothing here ever touches the photos themselves.
class DecisionStore {
  DecisionStore._(this._db);

  final Database _db;

  /// Opens the database at [path], creating it the first time. [factory] is
  /// sqflite's own on Android, and the FFI one on Windows and in tests.
  static Future<DecisionStore> open(
    DatabaseFactory factory,
    String path,
  ) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        // Version 1 had only decisions; version 2 added the trash table,
        // version 3 the settings one and version 5 the fingerprints (version
        // 4 had them without colour, and was never released). Whenever the
        // tables change, bump the version and add a step to onUpgrade, so
        // people who already use the app keep their data.
        version: 5,
        onCreate: (db, version) async {
          await db.execute(_createDecisionsTable);
          await db.execute(_createTrashTable);
          await db.execute(_createSettingsTable);
          await db.execute(_createFingerprintsTable);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await db.execute(_createTrashTable);
          if (oldVersion < 3) await db.execute(_createSettingsTable);
          // Fingerprints are only a cache of what the photos look like, so
          // when their shape changes, they're thrown away and made again.
          if (oldVersion < 5) {
            await db.execute('DROP TABLE IF EXISTS fingerprints');
            await db.execute(_createFingerprintsTable);
          }
        },
      ),
    );
    return DecisionStore._(db);
  }

  /// Every saved decision, oldest first.
  Future<List<DecisionRecord>> loadAll() async {
    final rows = await _db.query('decisions', orderBy: 'decided_at, rowid');
    return [
      for (final row in rows)
        DecisionRecord(
          row['photo_id']! as String,
          Decision.values.byName(row['decision']! as String),
        ),
    ];
  }

  /// Saves [decision] for [photoId], replacing any earlier one.
  Future<void> record(String photoId, Decision decision) async {
    await _db.insert('decisions', {
      'photo_id': photoId,
      'decision': decision.name,
      'decided_at': DateTime.now().microsecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Saves every decision in [decisions] (by photo id), in one transaction:
  /// all of them are saved, or none. They keep the order of the map in the
  /// undo history.
  Future<void> recordAll(Map<String, Decision> decisions) async {
    final batch = _db.batch();
    // Microseconds, one apart, so the group stays in order even if the
    // clock doesn't tick between them.
    var when = DateTime.now().microsecondsSinceEpoch;
    for (final MapEntry(key: photoId, value: decision) in decisions.entries) {
      batch.insert('decisions', {
        'photo_id': photoId,
        'decision': decision.name,
        'decided_at': when++,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Changes the saved decision for [photoId] without moving it in the
  /// undo order, e.g. when a photo is rescued on the review screen.
  Future<void> update(String photoId, Decision decision) async {
    await _db.update(
      'decisions',
      {'decision': decision.name},
      where: 'photo_id = ?',
      whereArgs: [photoId],
    );
  }

  /// Forgets the decision for [photoId], if there is one.
  Future<void> remove(String photoId) async {
    // `?` placeholders, never string interpolation: the database inserts the
    // value safely, so a strange file name can't change the SQL.
    await _db.delete('decisions', where: 'photo_id = ?', whereArgs: [photoId]);
  }

  /// Forgets the decisions for all of [photoIds], in one transaction.
  Future<void> removeAll(Iterable<String> photoIds) async {
    final batch = _db.batch();
    for (final photoId in photoIds) {
      batch.delete('decisions', where: 'photo_id = ?', whereArgs: [photoId]);
    }
    await batch.commit(noResult: true);
  }

  /// Remembers [photos] as moved to the trash and forgets their decisions,
  /// in one transaction so the two lists never disagree.
  Future<void> recordTrashed(List<TrashedPhoto> photos) async {
    final batch = _db.batch();
    for (final photo in photos) {
      batch.delete(
        'decisions',
        where: 'photo_id = ?',
        whereArgs: [photo.photoId],
      );
      batch.insert('trash', {
        'photo_id': photo.photoId,
        'name': photo.name,
        'trashed_at': photo.trashedAt.microsecondsSinceEpoch,
        'thumbnail_path': photo.thumbnailPath,
        'trash_path': photo.trashPath,
        'size_bytes': photo.sizeBytes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Photos the app moved to the trash, newest first.
  Future<List<TrashedPhoto>> loadTrashed() async {
    final rows = await _db.query(
      'trash',
      orderBy: 'trashed_at DESC, rowid DESC',
    );
    return [
      for (final row in rows)
        TrashedPhoto(
          photoId: row['photo_id']! as String,
          name: row['name']! as String,
          trashedAt: DateTime.fromMicrosecondsSinceEpoch(
            row['trashed_at']! as int,
          ),
          thumbnailPath: row['thumbnail_path'] as String?,
          trashPath: row['trash_path'] as String?,
          sizeBytes: row['size_bytes'] as int?,
        ),
    ];
  }

  /// Stops remembering [photoIds] as trashed: they were restored, or the
  /// system removed them for good.
  Future<void> forgetTrashed(Iterable<String> photoIds) async {
    final batch = _db.batch();
    for (final photoId in photoIds) {
      batch.delete('trash', where: 'photo_id = ?', whereArgs: [photoId]);
    }
    await batch.commit(noResult: true);
  }

  /// Every saved setting, by name. Settings never changed aren't saved, so
  /// they keep following the app's defaults.
  Future<Map<String, String>> loadSettings() async {
    final rows = await _db.query('settings');
    return {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  /// Saves [value] for the setting called [key], replacing any earlier one.
  Future<void> saveSetting(String key, String value) async {
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Every saved fingerprint, by photo id.
  Future<Map<String, SavedFingerprint>> loadFingerprints() async {
    final rows = await _db.query('fingerprints');
    return {
      for (final row in rows)
        row['photo_id']! as String: SavedFingerprint(
          row['photo_id']! as String,
          row['stamp']! as int,
          Fingerprint(
            row['hash']! as int,
            row['sharpness']! as double,
            row['colour']! as int,
          ),
        ),
    };
  }

  /// Saves [fingerprints], replacing earlier ones for the same photos, in
  /// one transaction.
  Future<void> saveFingerprints(Iterable<SavedFingerprint> fingerprints) async {
    final batch = _db.batch();
    for (final saved in fingerprints) {
      batch.insert('fingerprints', {
        'photo_id': saved.photoId,
        'stamp': saved.stamp,
        // A 64-bit whole number: SQLite's INTEGER holds one (signed), and so
        // does a Dart int on Android and Windows.
        'hash': saved.fingerprint.hash,
        'sharpness': saved.fingerprint.sharpness,
        'colour': saved.fingerprint.colour,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();
}

const _createDecisionsTable = '''
  CREATE TABLE decisions (
    photo_id   TEXT PRIMARY KEY,
    decision   TEXT NOT NULL CHECK (decision IN ('keep', 'delete')),
    decided_at INTEGER NOT NULL
  )
''';

const _createTrashTable = '''
  CREATE TABLE trash (
    photo_id       TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    trashed_at     INTEGER NOT NULL,
    thumbnail_path TEXT,
    trash_path     TEXT,
    size_bytes     INTEGER
  )
''';

// One row per setting, such as ('order', 'oldestFirst'). Text for every
// value, so a new setting never needs a new column.
const _createSettingsTable = '''
  CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
''';

// How each photo looks, to find look-alikes. Only ever worked out again for
// a photo whose date no longer matches [stamp].
const _createFingerprintsTable = '''
  CREATE TABLE fingerprints (
    photo_id  TEXT PRIMARY KEY,
    stamp     INTEGER NOT NULL,
    hash      INTEGER NOT NULL,
    sharpness REAL NOT NULL,
    colour    INTEGER NOT NULL
  )
''';
