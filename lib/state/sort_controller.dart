import 'package:flutter/foundation.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';

/// The state of sorting one album: which photo is next, what has been
/// decided, and undo. Screens listen to it and redraw when it changes.
///
/// Every decision is saved straight away, so opening the album again later
/// continues where the user stopped.
class SortController extends ChangeNotifier {
  SortController({
    required this.repository,
    required this.store,
    required this.album,
  });

  final PhotoRepository repository;
  final DecisionStore store;
  final Album album;

  List<Photo> _photos = [];
  final _decisions = <String, Decision>{};
  // Photo ids in the order they were decided, newest last. Undo pops from it.
  final _history = <String>[];
  // After an undo, the photo to show next, even if it isn't first in line.
  Photo? _undone;
  bool _loading = true;
  Object? _loadError;
  bool _disposed = false;

  bool get isLoading => _loading;
  Object? get loadError => _loadError;
  int get total => _photos.length;
  int get sortedCount => _decisions.length;
  int get keepCount =>
      _decisions.values.where((decision) => decision == Decision.keep).length;
  int get deleteCount => sortedCount - keepCount;
  bool get canUndo => _history.isNotEmpty;
  bool get isDone => !_loading && _loadError == null && current == null;

  /// The photo waiting for a decision, or null once everything is sorted.
  Photo? get current {
    if (_undone case final photo? when !_decisions.containsKey(photo.id)) {
      return photo;
    }
    return _photos
        .where((photo) => !_decisions.containsKey(photo.id))
        .firstOrNull;
  }

  /// Up to [count] photos waiting after [current], in order. Used to draw the
  /// card behind and to load images before the user reaches them.
  List<Photo> upcoming(int count) {
    final currentId = current?.id;
    return _photos
        .where(
          (photo) => photo.id != currentId && !_decisions.containsKey(photo.id),
        )
        .take(count)
        .toList();
  }

  /// Loads the album's photos and any decisions saved earlier.
  Future<void> load() async {
    try {
      _photos = await repository.photosIn(album);
      final inAlbum = {for (final photo in _photos) photo.id};
      for (final record in await store.loadAll()) {
        if (!inAlbum.contains(record.photoId)) continue;
        _decisions[record.photoId] = record.decision;
        _history.add(record.photoId);
      }
    } catch (error) {
      _loadError = error;
    }
    _loading = false;
    _notify();
  }

  /// Records [decision] for the current photo and moves on to the next one.
  Future<void> decide(Decision decision) async {
    final photo = current;
    if (photo == null) return;

    // Update the screen first so fast sorting feels instant, then save. If
    // saving fails, put everything back and let the caller show an error.
    _decisions[photo.id] = decision;
    _history.add(photo.id);
    _notify();
    try {
      await store.record(photo.id, decision);
    } catch (_) {
      _decisions.remove(photo.id);
      _history.remove(photo.id);
      _undone = photo;
      _notify();
      rethrow;
    }
  }

  /// Takes back the most recent decision and shows that photo again.
  Future<void> undo() async {
    if (_history.isEmpty) return;

    final photoId = _history.removeLast();
    final decision = _decisions.remove(photoId)!;
    final previous = _undone;
    _undone = _photos.firstWhere((photo) => photo.id == photoId);
    _notify();
    try {
      await store.remove(photoId);
    } catch (_) {
      _decisions[photoId] = decision;
      _history.add(photoId);
      _undone = previous;
      _notify();
      rethrow;
    }
  }

  /// Forgets every decision made in this album.
  Future<void> startOver() async {
    await store.removeAll(_photos.map((photo) => photo.id));
    _decisions.clear();
    _history.clear();
    _undone = null;
    _notify();
  }

  // The screen may close while a load or save is still running. Telling a
  // disposed controller's listeners about it would crash, so skip it.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
