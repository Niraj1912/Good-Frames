import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/trashed_photo.dart';
import 'package:sqflite/sqflite.dart';

/// One saved decision.
class DecisionRecord {
  const DecisionRecord(this.photoId, this.decision);

  final String photoId;
  final Decision decision;
}

/// Saves keep/delete decisions, and the list of photos moved to the trash,
/// in a SQLite database, so they survive the app being closed or killed.
/// Nothing here ever touches the photos themselves.
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
        // Version 1 had only decisions; version 2 added the trash table.
        // Whenever the tables change, bump the version and add a step to
        // onUpgrade, so people who already use the app keep their data.
        version: 2,
        onCreate: (db, version) async {
          await db.execute(_createDecisionsTable);
          await db.execute(_createTrashTable);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await db.execute(_createTrashTable);
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
