/// A group of photos the user can pick to sort, such as "Camera" or
/// "Screenshots". On Android these are the gallery's folders; on Windows,
/// the folders inside the test-photos folder.
class Album {
  const Album({required this.id, required this.name, required this.photoCount});

  /// Identifies the album to the repository that created it.
  final String id;

  final String name;

  final int photoCount;
}
