import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/photo_order.dart';

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
    this.order = PhotoOrder.newestFirst,
  });

  final PhotoRepository repository;
  final DecisionStore store;
  final Album album;

  /// The order photos come up for sorting.
  final PhotoOrder order;

  // The album's photos loaded so far, in album order, and their ids.
  List<Photo> _photos = [];
  final _inAlbum = <String>{};
  // Every saved decision, including ones for photos in other albums. Only
  // photos in [_inAlbum] are ever counted or shown.
  final _decisions = <String, Decision>{};
  // Photo ids in the order they were decided, newest last. Undo takes the
  // newest one that belongs to this album.
  final _history = <String>[];
  // After an undo, the photo to show next, even if it isn't first in line.
  Photo? _undone;
  bool _loading = true;
  final _fullyLoaded = Completer<void>();
  Object? _loadError;
  bool _disposed = false;

  /// True until the first page of photos has arrived.
  bool get isLoading => _loading;

  /// True once every page has arrived (or loading failed).
  bool get isFullyLoaded => _fullyLoaded.isCompleted;
  Object? get loadError => _loadError;
  int get loadedCount => _photos.length;

  /// How many photos the album has: from the album list until every page
  /// has arrived, then exact.
  int get total =>
      isFullyLoaded ? _photos.length : max(album.photoCount, _photos.length);
  int get sortedCount =>
      _photos.where((photo) => _decisions.containsKey(photo.id)).length;
  int get keepCount =>
      _photos.where((photo) => _decisions[photo.id] == Decision.keep).length;
  int get deleteCount => sortedCount - keepCount;
  bool get canUndo => _history.any(_inAlbum.contains);

  /// Every photo is sorted. Never true while later pages may still bring
  /// unsorted photos.
  bool get isDone => isFullyLoaded && _loadError == null && current == null;

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

  /// Photos marked for deletion, in album order.
  List<Photo> get markedForDelete => [
    for (final photo in _photos)
      if (_decisions[photo.id] == Decision.delete) photo,
  ];

  /// What was decided for [photo], or null if nothing yet (or it's gone).
  Decision? decisionFor(Photo photo) => _decisions[photo.id];

  /// Loads any decisions saved earlier, then the album's photos page by
  /// page, telling listeners after each page so sorting can start at once.
  Future<void> load() async {
    try {
      // Decisions first, so each photo shows as sorted the moment it loads.
      for (final record in await store.loadAll()) {
        _decisions[record.photoId] = record.decision;
        _history.add(record.photoId);
      }
      await for (final page in repository.photosIn(album, order: order)) {
        for (final photo in page) {
          // Skip repeats, in case the album changed while it was loading.
          if (_inAlbum.add(photo.id)) _photos.add(photo);
        }
        _loading = false;
        _notify();
      }
    } catch (error) {
      _loadError = error;
    }
    _loading = false;
    _fullyLoaded.complete();
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

  /// The decision [undo] would take back, or null if there's none.
  Decision? get lastDecision {
    final index = _history.lastIndexWhere(_inAlbum.contains);
    return index == -1 ? null : _decisions[_history[index]];
  }

  /// Takes back the most recent decision in this album and shows that photo
  /// again.
  Future<void> undo() async {
    final index = _history.lastIndexWhere(_inAlbum.contains);
    if (index == -1) return;

    final photoId = _history.removeAt(index);
    final decision = _decisions.remove(photoId)!;
    final previous = _undone;
    _undone = _photos.firstWhere((photo) => photo.id == photoId);
    _notify();
    try {
      await store.remove(photoId);
    } catch (_) {
      _decisions[photoId] = decision;
      _history.insert(index, photoId);
      _undone = previous;
      _notify();
      rethrow;
    }
  }

  /// Changes a decision already made, e.g. rescuing a photo on the review
  /// screen. The undo order stays as it was.
  Future<void> changeDecision(Photo photo, Decision decision) async {
    final previous = _decisions[photo.id];
    if (previous == null || previous == decision) return;

    _decisions[photo.id] = decision;
    _notify();
    try {
      await store.update(photo.id, decision);
    } catch (_) {
      _decisions[photo.id] = previous;
      _notify();
      rethrow;
    }
  }

  /// Moves every photo marked for deletion to the trash. Photos that weren't
  /// moved stay marked, so the user can try again. [onProgress] reports how
  /// far preparing a big batch has got.
  Future<TrashResult> trashMarked({
    void Function(int done, int total)? onProgress,
  }) async {
    // Every marked photo, not just those in the pages loaded so far.
    await _fullyLoaded.future;
    final marked = markedForDelete;
    if (marked.isEmpty) return const TrashResult(requested: 0, moved: 0);

    final trashed = await repository.moveToTrash(
      marked,
      onProgress: onProgress,
    );
    final movedIds = {for (final photo in trashed) photo.photoId};
    final moved = marked.where((photo) => movedIds.contains(photo.id));

    // The photos are gone whatever happens next, so update the screen first.
    _photos = [
      for (final photo in _photos)
        if (!movedIds.contains(photo.id)) photo,
    ];
    _inAlbum.removeAll(movedIds);
    for (final id in movedIds) {
      _decisions.remove(id);
      _history.remove(id);
    }
    if (_undone case final photo? when movedIds.contains(photo.id)) {
      _undone = null;
    }
    _notify();

    // Then list them as trashed and forget their decisions, in one database
    // transaction. If that fails, the photos are still safe in the trash;
    // they just won't appear on the Recently deleted screen.
    try {
      await store.recordTrashed(trashed);
    } catch (_) {}

    final vanished = movedIds.length < marked.length
        ? await _dropVanishedPhotos()
        : 0;

    return TrashResult(
      requested: marked.length,
      moved: movedIds.length,
      vanished: vanished,
      freedBytes: moved.fold(0, (sum, photo) => sum + (photo.sizeBytes ?? 0)),
    );
  }

  // Photos that couldn't be moved may have been deleted by another app in
  // the meantime. Ask the photo source again and stop tracking any that are
  // gone, so they don't stay "marked for deletion" forever. Returns how many.
  Future<int> _dropVanishedPhotos() async {
    final stillThere = {
      for (final photo
          in await repository.photosIn(album).expand((page) => page).toList())
        photo.id,
    };
    final gone = [
      for (final photo in _photos)
        if (!stillThere.contains(photo.id)) photo.id,
    ];
    if (gone.isEmpty) return 0;

    _photos = [
      for (final photo in _photos)
        if (stillThere.contains(photo.id)) photo,
    ];
    _inAlbum.removeAll(gone);
    for (final id in gone) {
      _decisions.remove(id);
      _history.remove(id);
    }
    _notify();
    try {
      await store.removeAll(gone);
    } catch (_) {} // Leftover rows for missing photos are never shown.
    return gone.length;
  }

  /// Forgets every decision made in this album, and only in this album.
  Future<void> startOver() async {
    await _fullyLoaded.future; // The whole album, not just the first pages.
    await store.removeAll(_inAlbum);
    _decisions.removeWhere((id, _) => _inAlbum.contains(id));
    _history.removeWhere(_inAlbum.contains);
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

/// What happened when the marked photos were moved to the trash.
class TrashResult {
  const TrashResult({
    required this.requested,
    required this.moved,
    this.vanished = 0,
    this.freedBytes = 0,
  });

  final int requested;
  final int moved;

  /// Photos that turned out to be already deleted by another app.
  final int vanished;

  /// Space freed, when the photo source knows file sizes (not on Android yet).
  final int freedBytes;

  /// Photos still there that couldn't be moved, e.g. open in another app.
  int get failed => requested - moved - vanished;

  /// The user said no, so nothing was moved.
  bool get cancelled => requested > 0 && moved == 0 && vanished == 0;
}
