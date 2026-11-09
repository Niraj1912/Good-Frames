import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/chosen_folder.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/photo_order.dart';
import 'package:good_frames/models/trashed_photo.dart';

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

  /// Reports the access the app has now, without asking the user anything.
  Future<AccessStatus> checkAccess();

  /// Opens the system settings page where the user can change access.
  Future<void> openAccessSettings();

  /// Lets a user with [AccessStatus.limited] change which photos they share.
  Future<void> changeSelectedPhotos();

  /// Albums with at least one photo. The first one is "All photos".
  Future<List<Album>> albums();

  /// Photos in [album] in [order], delivered in pages: a big album can be
  /// shown, and sorting can start, long before all of it has loaded.
  Stream<List<Photo>> photosIn(
    Album album, {
    PhotoOrder order = PhotoOrder.newestFirst,
  });

  /// The image for [photo], decoded at about [width] pixels wide. Decoding at
  /// screen size instead of full size keeps memory use low.
  ImageProvider imageFor(Photo photo, {required int width});

  /// The image for zooming in to check a photo: as much detail as is
  /// sensible, up to [maxSize] pixels on the long side. Much bigger in
  /// memory than [imageFor], so only for one photo at a time.
  ImageProvider detailImageFor(Photo photo, {int maxSize = 4096});

  /// A file holding [photo], for handing to another app (sharing). Null if
  /// one can't be made. May be a temporary copy, so it must not be deleted
  /// or changed by the caller.
  Future<File?> fileForSharing(Photo photo);

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

  /// Erases [photos], which must already be in the trash, for good: nothing
  /// can bring them back after this. Only for photos the user picked, after
  /// the app has warned them. Returns the ids of those erased, or none if
  /// the user cancelled.
  Future<Set<String>> deleteForever(List<TrashedPhoto> photos);

  /// True if photos can be moved into gallery folders (Android). Where it
  /// isn't, the app hides the swipe-down-to-file feature.
  bool get canMoveToFolders;

  /// The folders photos can be moved into, as paths like `Pictures/Trip`.
  /// Empty where that isn't known.
  Future<List<String>> existingFolders();

  /// Moves [photos] into [folder]: a plain name (a new album, or the one
  /// with that name) or the path of an existing folder. Returns the ids
  /// actually moved: all of them, some if others couldn't be, or none if the
  /// user cancelled. A moved photo keeps its id.
  Future<Set<String>> moveToFolder(List<Photo> photos, String folder);

  /// Frees anything kept only to show [photos], once they can no longer be
  /// restored.
  Future<void> forgetTrashed(List<TrashedPhoto> photos);
}

/// Photos from folders the user picks, rather than from the whole library,
/// for people who'd rather not share every photo. Each folder that holds
/// photos, inside the chosen ones, is an album.
abstract interface class ChosenFoldersRepository implements PhotoRepository {
  /// The folders shared so far, most recent first.
  Future<List<ChosenFolder>> chosenFolders();

  /// Opens the system's folder picker. Returns the folder picked, or null
  /// if the user backed out.
  Future<ChosenFolder?> chooseFolder();

  /// Stops sharing [folder] with the app. Its photos stay where they are.
  Future<void> forgetFolder(ChosenFolder folder);
}
