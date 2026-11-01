/// A folder the user shared with the app, instead of sharing every photo.
class ChosenFolder {
  const ChosenFolder({
    required this.uri,
    required this.name,
    required this.path,
  });

  /// Android's address for the folder, which also carries the access to it.
  /// Opaque: only the repository that made it should look inside.
  final String uri;

  /// The folder's own name, e.g. "Camera".
  final String name;

  /// Where it is on the phone, e.g. "DCIM/Camera".
  final String path;
}
