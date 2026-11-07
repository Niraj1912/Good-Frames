import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/image_decoding.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/state/similarity.dart';

/// Photos that look alike, with the one that looks best marked as the
/// suggestion.
class SimilarGroup {
  const SimilarGroup(this.photos, this.suggested);

  /// Oldest first. Always two or more.
  final List<Photo> photos;

  /// The position in [photos] of the sharpest one.
  final int suggested;
}

/// Looks through some photos for ones that look alike. For each photo it
/// works out a [Fingerprint] from a small copy, and keeps it in the database,
/// so a second search of the same photos is quick.
///
/// Only photos with another photo taken within ten minutes are looked at: a
/// photo that stands alone in time can't be part of a group, and skipping
/// those means most of a library never needs opening.
class SimilarController extends ChangeNotifier {
  SimilarController({
    required this.repository,
    required this.store,
    required this.photos,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  /// The photos to look through.
  final List<Photo> photos;

  /// How wide the small copy is. 128 pixels is plenty to see a photo's shape
  /// and whether it's blurred, and still quick to get from the phone.
  static const sampleWidth = 128;

  // How many small copies are fetched at once, as for the trash thumbnails.
  static const _batch = 8;

  // Fingerprints are saved after this many photos, so a search that's left
  // part-way keeps what it has done.
  static const _saveEvery = 40;

  int _looked = 0;
  int _toLookAt = 0;
  bool _scanning = true;
  Object? _error;
  List<SimilarGroup> _groups = const [];
  bool _disposed = false;

  /// How many of the photos worth looking at have been looked at.
  int get looked => _looked;

  /// How many photos are worth looking at: those with a neighbour in time.
  int get toLookAt => _toLookAt;

  /// True until the search is over.
  bool get isScanning => _scanning;

  /// Why the search stopped early, if it did.
  Object? get error => _error;

  /// The groups found. Complete once [isScanning] is false.
  List<SimilarGroup> get groups => _groups;

  /// Runs the search. Safe to call once.
  Future<void> scan() async {
    try {
      await _scan();
    } catch (error) {
      _error = error;
    }
    _scanning = false;
    _notify();
  }

  Future<void> _scan() async {
    final worth = Similarity.worthComparing([
      for (final photo in photos) photo.date,
    ]).toList()..sort();
    final candidates = [for (final i in worth) photos[i]];
    _toLookAt = candidates.length;

    // What's already known, if it's still true: a photo whose date has
    // changed was edited, so its fingerprint no longer describes it.
    final saved = await store.loadFingerprints();
    final prints = <String, Fingerprint>{};
    final todo = <Photo>[];
    for (final photo in candidates) {
      final known = saved[photo.id];
      if (known != null && known.stamp == _stamp(photo)) {
        prints[photo.id] = known.fingerprint;
      } else {
        todo.add(photo);
      }
    }
    _looked = prints.length;
    _notify();

    var unsaved = <SavedFingerprint>[];
    for (var start = 0; start < todo.length; start += _batch) {
      if (_disposed) return;
      final batch = todo.skip(start).take(_batch).toList();
      final results = await Future.wait(batch.map(_fingerprint));
      for (var i = 0; i < batch.length; i++) {
        final fingerprint = results[i];
        if (fingerprint == null) continue; // Can't be described: no group.
        prints[batch[i].id] = fingerprint;
        unsaved.add(
          SavedFingerprint(batch[i].id, _stamp(batch[i]), fingerprint),
        );
      }
      _looked += batch.length;
      if (unsaved.length >= _saveEvery) {
        await store.saveFingerprints(unsaved);
        unsaved = [];
      }
      _notify();
    }
    if (unsaved.isNotEmpty) await store.saveFingerprints(unsaved);
    if (_disposed) return;

    final known = [
      for (final photo in candidates)
        if (prints[photo.id] != null) photo,
    ];
    _groups = [
      for (final members in Similarity.group([
        for (final photo in known)
          (date: photo.date, fingerprint: prints[photo.id]!),
      ]))
        SimilarGroup(
          [for (final i in members) known[i]],
          Similarity.sharpest([for (final i in members) prints[known[i].id]!]),
        ),
    ];
  }

  // A small copy of [photo], turned into its fingerprint. Null if it can't
  // be opened or is too small to describe.
  Future<Fingerprint?> _fingerprint(Photo photo) async {
    final provider = repository.imageFor(photo, width: sampleWidth);
    try {
      final image = await decodeImage(provider)
          .timeout(const Duration(seconds: 10));
      try {
        final data = await image.toByteData(); // RGBA, 4 bytes a pixel
        if (data == null) return null;
        return Similarity.of(
          data.buffer.asUint8List(),
          image.width,
          image.height,
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null; // A photo that can't be opened just isn't in any group.
    } finally {
      // Thousands of tiny copies would fill Flutter's image cache, which is
      // limited by count, and push out the photos the sort screen has
      // already prepared. They're done with, so out they go.
      await provider.evict();
    }
  }

  static int _stamp(Photo photo) => Similarity.stamp(photo.date);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
