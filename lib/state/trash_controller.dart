import 'package:flutter/foundation.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/trashed_photo.dart';

/// The state of the Recently deleted screen: photos this app moved to the
/// trash, bringing them back, and erasing them for good.
class TrashController extends ChangeNotifier {
  TrashController({
    required this.repository,
    required this.store,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PhotoRepository repository;
  final DecisionStore store;

  // The clock, passed in so tests can pretend weeks have gone by.
  final DateTime Function() _now;

  List<TrashedPhoto> _photos = [];
  bool _loading = true;
  Object? _loadError;
  bool _disposed = false;

  bool get isLoading => _loading;
  Object? get loadError => _loadError;

  /// Trashed photos that can still be restored, newest first.
  List<TrashedPhoto> get photos => _photos;

  /// When the system will remove [photo] for good, or null if it never will.
  DateTime? expiresAt(TrashedPhoto photo) {
    final keepsFor = repository.trashKeepsFor;
    return keepsFor == null ? null : photo.trashedAt.add(keepsFor);
  }

  Duration? timeLeft(TrashedPhoto photo) =>
      expiresAt(photo)?.difference(_now());

  Future<void> load() async {
    try {
      final all = await store.loadTrashed();
      // Photos the system has already removed for good can't come back, so
      // stop listing them and free their thumbnails.
      final now = _now();
      final expired = [
        for (final photo in all)
          if (expiresAt(photo)?.isBefore(now) ?? false) photo,
      ];
      if (expired.isNotEmpty) {
        await repository.forgetTrashed(expired);
        await store.forgetTrashed(expired.map((photo) => photo.photoId));
      }
      _photos = [
        for (final photo in all)
          if (!expired.contains(photo)) photo,
      ];
    } catch (error) {
      _loadError = error;
    }
    _loading = false;
    _notify();
  }

  /// Brings [chosen] back from the trash. Returns how many came back: fewer
  /// if some had already gone, none if the user cancelled.
  Future<int> restore(List<TrashedPhoto> chosen) async {
    final restored = await repository.restoreFromTrash(chosen);
    await store.forgetTrashed(restored);
    _photos = [
      for (final photo in _photos)
        if (!restored.contains(photo.photoId)) photo,
    ];
    _notify();
    return restored.length;
  }

  /// Erases [chosen] for good. Returns how many were erased: none if the user
  /// cancelled. The screen asks "are you sure?" before calling this.
  Future<int> deleteForever(List<TrashedPhoto> chosen) async {
    final deleted = await repository.deleteForever(chosen);
    await store.forgetTrashed(deleted);
    _photos = [
      for (final photo in _photos)
        if (!deleted.contains(photo.photoId)) photo,
    ];
    _notify();
    return deleted.length;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
