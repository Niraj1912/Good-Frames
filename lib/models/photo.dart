/// One photo, wherever it comes from: a file on Windows or the Android
/// gallery.
class Photo {
  const Photo({
    required this.id,
    required this.name,
    required this.date,
    this.sizeBytes,
  });

  /// Identifies the photo to the repository that created it. Other code
  /// should treat it as an opaque label and never parse it.
  final String id;

  /// File name, for showing to the user.
  final String name;

  /// When the photo was taken or last changed.
  final DateTime date;

  /// File size, if the source can tell cheaply. Null on Android for now.
  final int? sizeBytes;
}
