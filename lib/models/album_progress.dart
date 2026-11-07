/// How far through an album the user has got, remembered between visits so
/// the album list can show it and offer to carry on.
class AlbumProgress {
  const AlbumProgress({
    required this.sorted,
    required this.kept,
    required this.deleted,
    required this.openedAt,
  });

  /// Photos decided so far (kept plus deleted).
  final int sorted;
  final int kept;
  final int deleted;

  /// When the album was last sorted in.
  final DateTime openedAt;

  /// The settings-table key an album's progress is saved under.
  static String keyFor(String albumId) => 'progress:$albumId';

  static const keyPrefix = 'progress:';

  /// Reads a saved value, or returns null if it's missing or garbled.
  static AlbumProgress? parse(String? value) {
    final parts = value?.split(',');
    if (parts == null || parts.length != 4) return null;
    final numbers = [for (final part in parts) int.tryParse(part)];
    if (numbers.contains(null)) return null;
    return AlbumProgress(
      sorted: numbers[0]!,
      kept: numbers[1]!,
      deleted: numbers[2]!,
      openedAt: DateTime.fromMillisecondsSinceEpoch(numbers[3]!),
    );
  }

  /// What's saved: four whole numbers.
  String encode() =>
      '$sorted,$kept,$deleted,${openedAt.millisecondsSinceEpoch}';

  /// The share of [total] that's sorted, from 0 to 1.
  double shareOf(int total) => total <= 0 ? 0 : (sorted / total).clamp(0, 1);
}
