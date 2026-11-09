import 'package:good_frames/data/decision_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A real SQLite database that lives only in memory, so every test starts
/// empty and leaves nothing behind. The "no isolate" factory runs database
/// calls on the test's own thread, which widget tests need.
Future<DecisionStore> openTestStore() =>
    DecisionStore.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
