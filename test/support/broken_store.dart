import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/fingerprint.dart';
import 'package:good_frames/models/trashed_photo.dart';

/// A store whose disk is "full": loading works, saving always fails.
class BrokenStore implements DecisionStore {
  @override
  Future<List<DecisionRecord>> loadAll() async => [];

  @override
  Future<void> record(String photoId, Decision decision) async =>
      throw Exception('disk full');

  @override
  Future<void> recordAll(Map<String, Decision> decisions) async =>
      throw Exception('disk full');

  @override
  Future<void> update(String photoId, Decision decision) async =>
      throw Exception('disk full');

  @override
  Future<void> remove(String photoId) async => throw Exception('disk full');

  @override
  Future<void> removeAll(Iterable<String> photoIds) async =>
      throw Exception('disk full');

  @override
  Future<void> recordTrashed(List<TrashedPhoto> photos) async =>
      throw Exception('disk full');

  @override
  Future<List<TrashedPhoto>> loadTrashed() async => [];

  @override
  Future<void> forgetTrashed(Iterable<String> photoIds) async =>
      throw Exception('disk full');

  @override
  Future<Map<String, String>> loadSettings() async => {};

  @override
  Future<void> saveSetting(String key, String value) async =>
      throw Exception('disk full');

  @override
  Future<Map<String, SavedFingerprint>> loadFingerprints() async => {};

  @override
  Future<void> saveFingerprints(
    Iterable<SavedFingerprint> fingerprints,
  ) async => throw Exception('disk full');

  @override
  Future<void> close() async {}
}
