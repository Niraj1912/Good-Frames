/// Checks a folder name typed by the user, for photos to be moved into.
/// Returns the cleaned name, or null if it can't be used.
///
/// The folder becomes `Pictures/name` in the gallery, so it must be one plain
/// name: no slashes (which would reach into other folders), no `..`, nothing
/// Android's file system refuses, and nothing starting with a dot (which
/// would hide it from the gallery).
String? cleanFolderName(String input) {
  final name = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty || name.length > 64) return null;
  if (name.startsWith('.')) return null;
  if (RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(name)) return null;
  return name;
}
