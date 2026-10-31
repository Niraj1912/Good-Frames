import 'package:flutter/painting.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';

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

  /// Asks the user for access if needed, and reports what they allowed.
  Future<AccessStatus> requestAccess();

  /// Opens the system settings page where the user can change access.
  Future<void> openAccessSettings();

  /// Lets a user with [AccessStatus.limited] change which photos they share.
  Future<void> changeSelectedPhotos();

  /// Albums with at least one photo. The first one is "All photos".
  Future<List<Album>> albums();

  /// Photos in [album], newest first.
  Future<List<Photo>> photosIn(Album album);

  /// The image for [photo], decoded at about [width] pixels wide. Decoding at
  /// screen size instead of full size keeps memory use low.
  ImageProvider imageFor(Photo photo, {required int width});
}
