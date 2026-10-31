import 'package:photo_swipe/models/decision.dart';
import 'package:sqflite/sqflite.dart';

/// One saved decision.
class DecisionRecord {
  const DecisionRecord(this.photoId, this.decision);

  final String photoId;
  final Decision decision;
}

/// Saves keep/delete decisions in a SQLite database, so sorting survives the
/// app being closed or killed. It only stores decisions: nothing here ever
/// touches the photos themselves.
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
        // Bump the version and add an onUpgrade step whenever the table
        // changes, so existing users' saved decisions are kept.
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE decisions (
            photo_id   TEXT PRIMARY KEY,
            decision   TEXT NOT NULL CHECK (decision IN ('keep', 'delete')),
            decided_at INTEGER NOT NULL
          )
        '''),
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

  Future<void> close() => _db.close();
}
