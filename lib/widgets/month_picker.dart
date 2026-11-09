import 'package:flutter/material.dart';
import 'package:good_frames/state/sort_controller.dart';
import 'package:good_frames/theme/app_theme.dart';
import 'package:good_frames/theme/glass.dart';
import 'package:good_frames/widgets/formatting.dart';

/// The sort screen's title: the album's name, with the month being sorted
/// under it ("All months"), which opens the month picker. Just the name
/// when there's no month to pick.
class SortTitle extends StatelessWidget {
  const SortTitle({
    super.key,
    required this.albumName,
    required this.month,
    required this.onPickMonth,
  });

  final String albumName;
  final DateTime? month;

  /// Null when the album's photos are all from one month.
  final VoidCallback? onPickMonth;

  @override
  Widget build(BuildContext context) {
    final name = Text(albumName, overflow: TextOverflow.ellipsis);
    final onPickMonth = this.onPickMonth;
    if (onPickMonth == null) return name;

    final theme = Theme.of(context);
    // In the accent blue, which marks things to tap.
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      onTapHint: 'choose a month',
      child: InkWell(
        onTap: onPickMonth,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              name,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      switch (month) {
                        final month? => formatMonth(month),
                        null => 'All months',
                      },
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 20, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the user choose one month of the album to sort, or all of them.
/// Each month shows how much of it is sorted, so it's easy to see which are
/// done. It keeps up while the album is still loading.
Future<void> showMonthPicker(BuildContext context, SortController controller) {
  return showModalBottomSheet<void>(
    context: context,
    // The sheet is a pane of glass, so the sheet itself is see-through.
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Glass(
        // The photo may be behind it, so the glass hides more of it, and
        // blurs it for real: the one pane that needs to.
        tint: GlassColors.of(context).overPhotos,
        blur: true,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        // On the glass, so taps ripple over it rather than under it.
        child: Material(
          type: MaterialType.transparency,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              void choose(DateTime? month) {
                controller.showMonth(month);
                Navigator.pop(context);
              }

              final months = controller.months;
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  const _DragHandle(),
                  _MonthTile(
                    label: 'All months',
                    photos: months.fold(0, (sum, month) => sum + month.photos),
                    sorted: months.fold(0, (sum, month) => sum + month.sorted),
                    selected: controller.month == null,
                    onTap: () => choose(null),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  for (final month in months)
                    _MonthTile(
                      label: formatMonth(month.month),
                      photos: month.photos,
                      sorted: month.sorted,
                      selected: controller.month == month.month,
                      onTap: () => choose(month.month),
                    ),
                  if (!controller.isFullyLoaded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        'Loading ${formatCount(controller.loadedCount)} of '
                        '${formatCount(controller.album.photoCount)} photos…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// The little bar at the top of the sheet that shows it can be dragged.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// One row of the month picker: "October 2026 · 108 / 310", with a green
/// tick once the month is all sorted.
class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.label,
    required this.photos,
    required this.sorted,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int photos;
  final int sorted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = sorted == photos;
    return ListTile(
      title: Text(label),
      selected: selected,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            Icon(
              Icons.check,
              size: 18,
              color: SortColors.of(context).keep,
              semanticLabel: 'all sorted',
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${formatCount(sorted)} / ${formatCount(photos)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
