import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/album_progress.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/photo_order.dart';

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

  // The album's photos loaded so far, in album order, and the same photos
  // by id.
  List<Photo> _photos = [];
  final _byId = <String, Photo>{};
  // Every saved decision, including ones for photos in other albums. Only
  // photos in [_byId] are ever counted or shown.
  final _decisions = <String, Decision>{};
  // The month being sorted (its first day), or null for the whole album.
  DateTime? _month;
  // The number of the last set of decisions made together (see
  // decideMany); 0 is never used, as it means "on its own".
  int _lastGroup = 0;
  // Photos swiped down, by id: the gallery folder each will be moved into.
  // Each is also a Keep in [_decisions]. Saved, so a swipe survives the app
  // being closed before the move.
  final _filing = <String, String>{};
  // Photos put off for later, in the order they were put off (a map keeps
  // the order things were added). Not saved: only for this visit.
  final _later = <String, Photo>{};
  // What undo can take back, newest last: decisions, and photos put off.
  // Undo takes the newest one that belongs to this album.
  final _history = <_Step>[];
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

  /// The month being sorted (its first day), or null for the whole album.
  /// Everything else here (the counts, the queue, undo, review and start
  /// over) covers only the photos being sorted.
  DateTime? get month => _month;

  /// Sorts only the photos taken in [month], or the whole album if null.
  void showMonth(DateTime? month) {
    _month = month == null ? null : DateTime(month.year, month.month);
    _notify();
  }

  /// How many photos are being sorted. For the whole album: the album
  /// list's count until every page has arrived, then exact. For a month:
  /// those loaded so far.
  int get total {
    if (_month != null) return _shown.length;
    return isFullyLoaded
        ? _photos.length
        : max(album.photoCount, _photos.length);
  }

  int get sortedCount =>
      _shown.where((photo) => _decisions.containsKey(photo.id)).length;
  int get keepCount =>
      _shown.where((photo) => _decisions[photo.id] == Decision.keep).length;
  int get deleteCount => sortedCount - keepCount;

  /// Photos swiped down that are still waiting to be moved to their folder.
  int get filedCount => _shown.where((p) => _filing.containsKey(p.id)).length;

  /// Those photos, in album order, with the folder each is going to.
  List<({Photo photo, String folder})> get filedPhotos => [
    for (final photo in _shown)
      if (_filing[photo.id] case final folder?) (photo: photo, folder: folder),
  ];

  /// The folder [photo] is waiting to be moved to, or null.
  String? folderFor(Photo photo) => _filing[photo.id];

  bool get canUndo => _history.any((step) => _isShown(step.photoId));

  /// Photos put off for later that are still waiting to come back.
  int get laterCount {
    final currentId = current?.id;
    return _later.values
        .where((photo) => photo.id != currentId && _inMonth(photo))
        .length;
  }

  /// Each month the album's photos (loaded so far) were taken in, with how
  /// many photos it has and how many are sorted. In the order photos come
  /// up: newest month first, unless sorting oldest first.
  List<MonthCount> get months {
    final photos = <DateTime, int>{};
    final sorted = <DateTime, int>{};
    for (final photo in _photos) {
      final month = monthOf(photo);
      photos.update(month, (count) => count + 1, ifAbsent: () => 1);
      if (_decisions.containsKey(photo.id)) {
        sorted.update(month, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final list = [
      for (final MapEntry(key: month, value: count) in photos.entries)
        (month: month, photos: count, sorted: sorted[month] ?? 0),
    ]..sort((a, b) => a.month.compareTo(b.month));
    return order == PhotoOrder.newestFirst ? list.reversed.toList() : list;
  }

  /// Once [month] is done: the next month in [months] with photos still to
  /// sort (or the first one before it), or null if every month is done.
  DateTime? get nextMonth {
    final month = _month;
    if (month == null) return null;
    final list = months;
    final at = list.indexWhere((entry) => entry.month == month);
    for (final entry in [...list.skip(at + 1), ...list.take(max(at, 0))]) {
      if (entry.sorted < entry.photos) return entry.month;
    }
    return null;
  }

  /// The month [photo] was taken in, as the first day of that month.
  static DateTime monthOf(Photo photo) =>
      DateTime(photo.date.year, photo.date.month);

  bool _inMonth(Photo photo) => _month == null || monthOf(photo) == _month;

  // The photos being sorted: the whole album, or one month of it.
  Iterable<Photo> get _shown =>
      _month == null ? _photos : _photos.where(_inMonth);

  bool _isShown(String photoId) => switch (_byId[photoId]) {
    final photo? => _inMonth(photo),
    null => false,
  };

  /// Every photo is sorted. Never true while later pages may still bring
  /// unsorted photos.
  bool get isDone => isFullyLoaded && _loadError == null && current == null;

  /// The photo waiting for a decision, or null once everything is sorted.
  Photo? get current => _queue.firstOrNull;

  /// Up to [count] photos waiting after [current], in order. Used to draw the
  /// card behind and to load images before the user reaches them.
  List<Photo> upcoming(int count) => _queue.skip(1).take(count).toList();

  /// The photos for the film strip: up to [before] ahead of [current] in the
  /// album, then [current], then the next [after] to come up. Each has its
  /// place in the album, counting from 1. Once everything is sorted there is
  /// no current photo, so it's the last few.
  List<({Photo photo, int number, Decision? decision, bool isCurrent})>
  stripFrames({int before = 4, int after = 2}) {
    final shown = _shown.toList();
    final numbers = {for (final (i, photo) in shown.indexed) photo.id: i + 1};
    final now = current;
    final at = now == null ? shown.length : numbers[now.id]! - 1;
    ({Photo photo, int number, Decision? decision, bool isCurrent}) frame(
      Photo photo, {
      bool isCurrent = false,
    }) => (
      photo: photo,
      number: numbers[photo.id]!,
      decision: _decisions[photo.id],
      isCurrent: isCurrent,
    );
    final frames = [
      for (final photo in shown.sublist(max(0, at - before), at)) frame(photo),
      if (now != null) frame(now, isCurrent: true),
    ];
    // Photos put off for later can come up again from earlier in the album,
    // so skip any the strip already shows.
    final shownIds = {for (final f in frames) f.photo.id};
    return [
      ...frames,
      for (final photo in upcoming(after))
        if (shownIds.add(photo.id)) frame(photo),
    ];
  }

  // Every photo still waiting for a decision, in the order they come up.
  Iterable<Photo> get _queue sync* {
    // After an undo, that photo first.
    final undone = _undone;
    if (undone != null &&
        !_decisions.containsKey(undone.id) &&
        _inMonth(undone)) {
      yield undone;
    }
    for (final photo in _shown) {
      if (photo.id != undone?.id &&
          !_decisions.containsKey(photo.id) &&
          !_later.containsKey(photo.id)) {
        yield photo;
      }
    }
    // Then the photos put off for later. Not while pages are still loading,
    // or they'd come back ahead of photos that haven't arrived yet.
    if (!isFullyLoaded) return;
    for (final photo in _later.values) {
      if (photo.id != undone?.id && _inMonth(photo)) yield photo;
    }
  }

  /// Photos marked for deletion, in album order.
  List<Photo> get markedForDelete => [
    for (final photo in _shown)
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
        _history.add((photoId: record.photoId, later: false, group: 0));
      }
      _filing.addAll(await store.loadPendingMoves());
      await for (final page in repository.photosIn(album, order: order)) {
        for (final photo in page) {
          // Skip repeats, in case the album changed while it was loading.
          if (_byId.containsKey(photo.id)) continue;
          _byId[photo.id] = photo;
          _photos.add(photo);
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
  /// With a [folder] (only for Keep), the photo is also queued to be moved
  /// into that gallery folder later, from the review screen.
  Future<void> decide(Decision decision, {String? folder}) async {
    final photo = current;
    if (photo == null) return;
    final filing = decision == Decision.keep ? folder : null;

    // Update the screen first so fast sorting feels instant, then save. If
    // saving fails, put everything back and let the caller show an error.
    final step = (photoId: photo.id, later: false, group: 0);
    final wasLater = _later.remove(photo.id) != null;
    _decisions[photo.id] = decision;
    if (filing != null) _filing[photo.id] = filing;
    _history.add(step);
    _notify();
    try {
      if (filing == null) {
        await store.record(photo.id, decision);
      } else {
        await store.recordFiled(photo.id, filing);
      }
    } catch (_) {
      _decisions.remove(photo.id);
      _filing.remove(photo.id);
      _history.remove(step);
      if (wasLater) _later[photo.id] = photo;
      _undone = photo;
      _notify();
      rethrow;
    }
  }

  /// Decides several photos at once, such as keeping one of eight look-alikes
  /// and marking the rest for deletion. [choices] is by photo id. Photos that
  /// aren't being sorted here, or already have a decision, are left out.
  ///
  /// It's saved in one go (all or nothing), and one undo takes the whole set
  /// back, however many photos it covered.
  Future<void> decideMany(Map<String, Decision> choices) async {
    final todo = {
      for (final MapEntry(key: id, value: decision) in choices.entries)
        if (_byId[id] case final photo?
            when _inMonth(photo) && !_decisions.containsKey(id))
          id: decision,
    };
    if (todo.isEmpty) return;

    // As in decide(): update the screen first, then save, and put it all
    // back if saving fails.
    final group = ++_lastGroup;
    final steps = [
      for (final id in todo.keys) (photoId: id, later: false, group: group),
    ];
    final wasLater = {for (final id in todo.keys) id: ?_later[id]};
    final previous = _undone;
    wasLater.keys.forEach(_later.remove);
    _decisions.addAll(todo);
    _history.addAll(steps);
    if (_undone case final photo? when todo.containsKey(photo.id)) {
      _undone = null;
    }
    _notify();
    try {
      await store.recordAll(todo);
    } catch (_) {
      todo.keys.forEach(_decisions.remove);
      _history.removeWhere(steps.contains);
      _later.addAll(wasLater);
      _undone = previous;
      _notify();
      rethrow;
    }
  }

  /// Puts the current photo off: it comes back once every other photo being
  /// sorted is done. Nothing is saved, so if the album is closed it's
  /// simply unsorted, in its usual place, next time.
  void putOff() {
    final photo = current;
    if (photo == null) return;

    if (_undone?.id == photo.id) _undone = null;
    // Put off again: it goes to the back of the line.
    _later.remove(photo.id);
    _later[photo.id] = photo;
    _history.add((photoId: photo.id, later: true, group: 0));
    _notify();
  }

  /// The decision [undo] would take back, or null if there's none or it
  /// would take back putting a photo off ([lastWasPutOff]).
  Decision? get lastDecision => switch (_lastStep) {
    (:final photoId, later: false, group: 0) => _decisions[photoId],
    _ => null,
  };

  /// Whether [undo] would take back a photo swiped down into a folder, so
  /// it can come back from below.
  bool get lastWasFiled => switch (_lastStep) {
    (:final photoId, later: false, group: 0) => _filing.containsKey(photoId),
    _ => false,
  };

  /// Whether [undo] would bring back a photo that was put off for later.
  bool get lastWasPutOff => _lastStep?.later ?? false;

  _Step? get _lastStep {
    final index = _lastStepIndex;
    return index == -1 ? null : _history[index];
  }

  int get _lastStepIndex =>
      _history.lastIndexWhere((step) => _isShown(step.photoId));

  /// Takes back the most recent decision among the photos being sorted, or
  /// putting one off, and shows that photo again.
  Future<void> undo() async {
    final index = _lastStepIndex;
    if (index == -1) return;

    // Photos decided together are taken back together.
    final group = _history[index].group;
    if (group != 0) return _undoGroup(group);

    final step = _history.removeAt(index);
    final photo = _byId[step.photoId]!;
    final previous = _undone;
    _undone = photo;

    if (step.later) {
      // Out of the later line, unless it was put off before this too.
      if (!_history.any((other) => other.photoId == photo.id && other.later)) {
        _later.remove(photo.id);
      }
      _notify();
      return;
    }

    final decision = _decisions.remove(photo.id)!;
    final folder = _filing.remove(photo.id);
    _notify();
    try {
      await store.remove(photo.id);
    } catch (_) {
      _decisions[photo.id] = decision;
      if (folder != null) _filing[photo.id] = folder;
      _history.insert(index, step);
      _undone = previous;
      _notify();
      rethrow;
    }
  }

  // Takes back every decision made together as [group], in one go.
  Future<void> _undoGroup(int group) async {
    final taken = <int, _Step>{
      for (var i = 0; i < _history.length; i++)
        if (_history[i].group == group) i: _history[i],
    };
    for (final i in taken.keys.toList().reversed) {
      _history.removeAt(i);
    }
    final ids = [for (final step in taken.values) step.photoId];
    final decisions = {for (final id in ids) id: ?_decisions.remove(id)};
    final previous = _undone;
    _undone = _byId[ids.first];
    _notify();
    try {
      await store.removeAll(ids);
    } catch (_) {
      _decisions.addAll(decisions);
      for (final MapEntry(key: i, value: step) in taken.entries) {
        _history.insert(i, step); // Smallest first, so each lands in place.
      }
      _undone = previous;
      _notify();
      rethrow;
    }
  }

  /// The photos being sorted (the album, or the month shown) that have no
  /// decision yet, in album order. What a search for look-alikes covers:
  /// photos already sorted are never offered again.
  List<Photo> get unsortedPhotos => [
    for (final photo in _shown)
      if (!_decisions.containsKey(photo.id)) photo,
  ];

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

  /// Stops waiting to move [photo]: it stays a Keep, where it is.
  Future<void> unfile(Photo photo) async {
    final folder = _filing.remove(photo.id);
    if (folder == null) return;
    _notify();
    try {
      await store.clearPendingMoves([photo.id]);
    } catch (_) {
      _filing[photo.id] = folder;
      _notify();
      rethrow;
    }
  }

  /// Queues [photo] again for [folder], after [unfile] on the review screen.
  Future<void> refile(Photo photo, String folder) async {
    if (!_byId.containsKey(photo.id) || _filing.containsKey(photo.id)) return;
    _filing[photo.id] = folder;
    _notify();
    try {
      await store.recordFiled(photo.id, folder);
    } catch (_) {
      _filing.remove(photo.id);
      _notify();
      rethrow;
    }
  }

  /// Moves every photo swiped down into its gallery folder. Photos that
  /// couldn't be moved stay queued, so the user can try again. Moved photos
  /// stay Keeps with the same id, so nothing about them is lost.
  Future<MoveResult> moveFiled() async {
    await _fullyLoaded.future; // Every queued photo, not just those loaded.
    final byFolder = <String, List<Photo>>{};
    for (final (:photo, :folder) in filedPhotos) {
      (byFolder[folder] ??= []).add(photo);
    }
    final requested = byFolder.values.fold(0, (sum, list) => sum + list.length);
    if (requested == 0) return const MoveResult(requested: 0, moved: 0);

    final movedIds = <String>{};
    final folders = <String>{};
    for (final MapEntry(key: folder, value: photos) in byFolder.entries) {
      final moved = await repository.moveToFolder(photos, folder);
      // Nothing moved: the user said no (or nothing could move), so don't
      // ask again for the next folder.
      if (moved.isEmpty) break;
      movedIds.addAll(moved);
      folders.add(folder);
    }
    _filing.removeWhere((id, _) => movedIds.contains(id));
    _notify();
    // If this fails, the photos have still moved; the leftover rows are
    // harmless, as moving a photo to where it already is changes nothing.
    try {
      await store.clearPendingMoves(movedIds);
    } catch (_) {}
    return MoveResult(
      requested: requested,
      moved: movedIds.length,
      folders: folders,
    );
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
    _drop(movedIds);
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

    _drop(gone.toSet());
    _notify();
    try {
      await store.removeAll(gone);
    } catch (_) {} // Leftover rows for missing photos are never shown.
    return gone.length;
  }

  /// Forgets every decision about the photos being sorted (the album, or
  /// the month), and nothing else.
  Future<void> startOver() async {
    await _fullyLoaded.future; // The whole album, not just the first pages.
    final ids = {for (final photo in _shown) photo.id};
    await store.removeAll(ids);
    _forget(ids);
    _undone = null;
    _notify();
  }

  // Stops tracking anything about these photos: decisions, undo steps and
  // putting off.
  void _forget(Set<String> ids) {
    _decisions.removeWhere((id, _) => ids.contains(id));
    _filing.removeWhere((id, _) => ids.contains(id));
    _history.removeWhere((step) => ids.contains(step.photoId));
    _later.removeWhere((id, _) => ids.contains(id));
  }

  // Stops tracking photos that have left the album: moved to the trash, or
  // deleted by another app.
  void _drop(Set<String> ids) {
    _photos = [
      for (final photo in _photos)
        if (!ids.contains(photo.id)) photo,
    ];
    ids.forEach(_byId.remove);
    _forget(ids);
    if (_undone case final photo? when ids.contains(photo.id)) _undone = null;
    // A month with no photos left has nothing to show.
    if (_month != null && !_photos.any(_inMonth)) _month = null;
  }

  // The screen may close while a load or save is still running. Telling a
  // disposed controller's listeners about it would crash, so skip it.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
    _saveProgress();
  }

  // What was last saved, so nothing is written when nothing changed.
  String? _savedProgress;

  // Remembers how far through the album the user is, for the album list.
  // Only once every photo has loaded, so the counts are for the whole album.
  // It's a convenience, so if it can't be saved, nothing is said.
  void _saveProgress() {
    if (!isFullyLoaded || _loadError != null) return;
    var kept = 0;
    var deleted = 0;
    for (final photo in _photos) {
      switch (_decisions[photo.id]) {
        case Decision.keep:
          kept++;
        case Decision.delete:
          deleted++;
        case null:
      }
    }
    final key = '$kept,$deleted';
    if (key == _savedProgress) return;
    _savedProgress = key;
    final progress = AlbumProgress(
      sorted: kept + deleted,
      kept: kept,
      deleted: deleted,
      openedAt: DateTime.now(),
    );
    store
        .saveSetting(AlbumProgress.keyFor(album.id), progress.encode())
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One thing undo can take back: a decision about a photo, or putting it
/// off for later. Decisions made together, such as for a group of
/// look-alikes, share a nonzero [group] and are taken back together.
typedef _Step = ({String photoId, bool later, int group});

/// A month of an album, for choosing which month to sort: its first day,
/// how many photos were taken in it, and how many of those are sorted.
typedef MonthCount = ({DateTime month, int photos, int sorted});

/// What happened when the photos swiped down were moved into folders.
class MoveResult {
  const MoveResult({
    required this.requested,
    required this.moved,
    this.folders = const {},
  });

  final int requested;
  final int moved;

  /// The folders that received photos.
  final Set<String> folders;

  /// Photos that stayed queued: couldn't be moved, or the user said no.
  int get failed => requested - moved;

  /// The user said no, so nothing was moved.
  bool get cancelled => requested > 0 && moved == 0;
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
