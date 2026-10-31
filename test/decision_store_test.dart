import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/models/decision.dart';
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

  test('can forget one decision or several', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await store.record(id, Decision.keep);
    }

    await store.remove('a');
    await store.removeAll(['b', 'c']);

    expect((await store.loadAll()).map((record) => record.photoId), ['d']);
  });

  test('decisions survive closing and reopening the database', () async {
    final folder = await Directory.systemTemp.createTemp('swipesort_db_');
    addTearDown(() => folder.delete(recursive: true));
    final path = p.join(folder.path, 'decisions.db');

    final first = await DecisionStore.open(databaseFactoryFfiNoIsolate, path);
    await first.record('a', Decision.keep);
    await first.close();

    final second = await DecisionStore.open(databaseFactoryFfiNoIsolate, path);
    addTearDown(second.close);
    expect((await second.loadAll()).single.photoId, 'a');
  });
}
