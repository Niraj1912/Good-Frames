import 'package:flutter/painting.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/models/trashed_photo.dart';

/// How much of the photo library the user lets the app see.
enum AccessStatus {
  /// Every photo.
  granted,

  /// Only photos the user picked (Android 14+ "Select photos").
  limited,

  /// None. The user said no, or turned access off in Settings.
  denied,
}

/// Where photos come from. Screens only ever talk to this interface, so the
/// same UI works with the Android gallery, a folder on Windows, or fake data
/// in tests.
abstract interface class PhotoRepository {
  /// Names the photo source in messages, e.g. "No photos found in ...".
  String get sourceName;

  /// Something worth telling the user about the last scan, shown on the
  /// album list (e.g. files that had to be skipped), or null.
  String? get notice;

  /// Asks the user for access if needed, and reports what they allowed.
  Future<AccessStatus> requestAccess();

  /// Opens the system settings page where the user can change access.
  Future<void> openAccessSettings();

  /// Lets a user with [AccessStatus.limited] change which photos they share.
  Future<void> changeSelectedPhotos();

  /// Albums with at least one photo. The first one is "All photos".
  Future<List<Album>> albums();

  /// Photos in [album], newest first, delivered in pages: a big album can be
  /// shown, and sorting can start, long before all of it has loaded.
  Stream<List<Photo>> photosIn(Album album);

  /// The image for [photo], decoded at about [width] pixels wide. Decoding at
  /// screen size instead of full size keeps memory use low.
  ImageProvider imageFor(Photo photo, {required int width});

  /// The image for zooming in to check a photo: as much detail as is
  /// sensible, up to [maxSize] pixels on the long side. Much bigger in
  /// memory than [imageFor], so only for one photo at a time.
  ImageProvider detailImageFor(Photo photo, {int maxSize = 4096});

  /// True if the system shows its own "are you sure?" prompt when photos are
  /// moved to the trash, as Android does. Otherwise the app has to ask.
  bool get confirmsTrashItself;

  /// Tells the user where trashed photos go and how to get them back.
  String get trashExplanation;

  /// How long the trash keeps photos before the system removes them for
  /// good, or null if it never does.
  Duration? get trashKeepsFor;

  /// Moves [photos] to the trash, never deleting them outright. Returns a
  /// record of each photo actually moved: all of them, some if others
  /// couldn't be moved, or none if the user cancelled. [onProgress] reports
  /// how far the preparation has got, for big batches.
  Future<List<TrashedPhoto>> moveToTrash(
    List<Photo> photos, {
    void Function(int done, int total)? onProgress,
  });

  /// Brings [photos] back from the trash. Returns the ids of those restored.
  Future<Set<String>> restoreFromTrash(List<TrashedPhoto> photos);

  /// Frees anything kept only to show [photos], once they can no longer be
  /// restored.
  Future<void> forgetTrashed(List<TrashedPhoto> photos);
}
