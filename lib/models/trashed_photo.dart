/// A photo the app moved to the trash, remembered so it can be listed on the
/// Recently deleted screen and restored.
class TrashedPhoto {
  const TrashedPhoto({
    required this.photoId,
    required this.name,
    required this.trashedAt,
    this.thumbnailPath,
    this.trashPath,
    this.sizeBytes,
  });

  /// The photo's id from before it was trashed.
  final String photoId;
  final String name;
  final DateTime trashedAt;

  /// A small image file on this device to show the photo by, because the
  /// photo itself may be hidden while it's in the trash. Null if none could
  /// be made.
  final String? thumbnailPath;

  /// Where the file is now, when the trash is an ordinary folder (Windows).
  final String? trashPath;

  final int? sizeBytes;
}
