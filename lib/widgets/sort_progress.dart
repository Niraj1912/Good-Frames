import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/formatting.dart';

/// How far through the album the user is: a bar, plus the counts.
class SortProgress extends StatelessWidget {
  const SortProgress({
    super.key,
    required this.sorted,
    required this.total,
    required this.kept,
    required this.deleted,
    this.later = 0,
  });

  final int sorted;
  final int total;
  final int kept;
  final int deleted;

  /// Photos put off for later, still waiting to come back.
  final int later;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SortColors.of(context);
    final counts = theme.textTheme.labelLarge?.copyWith(
      fontFeatures: AppTheme.tabularFigures,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          // Two colours, so the bar shows the keep/delete split at a glance,
          // and glides to each new value instead of jumping.
          TweenAnimationBuilder<Offset>(
            tween: Tween(
              end: total == 0
                  ? Offset.zero
                  : Offset(kept / total, deleted / total),
            ),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, shares, _) => _SplitBar(
              keptShare: shares.dx,
              deletedShare: shares.dy,
              keepColor: colors.keep,
              deleteColor: colors.delete,
              trackColor: theme.colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(height: 10),
          // A Wrap, not a Row: with large text on a small phone the counts
          // move onto a second line instead of running off the screen.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                '${formatCount(sorted)} / ${formatCount(total)} sorted',
                style: counts,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CountChip(
                    label: 'Keep',
                    count: kept,
                    icon: Icons.check,
                    colour: colors.keep,
                  ),
                  const SizedBox(width: 8),
                  _CountChip(
                    label: 'Delete',
                    count: deleted,
                    icon: Icons.close,
                    colour: colors.delete,
                  ),
                  // Only while there are some, so it's clear where they went.
                  // In the accent blue: not keep or delete, just not yet.
                  if (later > 0) ...[
                    const SizedBox(width: 8),
                    _CountChip(
                      label: 'Later',
                      count: later,
                      icon: Icons.schedule,
                      colour: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A count on a soft wash of its meaning colour, with the same icon as its
/// button: the small version of the totals at the end of an album. Read
/// out as one phrase, such as "Keep 12".
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.colour,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label ${formatCount(count)}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Faint enough that the coloured number on it stays readable.
          color: Color.alphaBlend(
            colour.withValues(alpha: 0.03),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colour),
              const SizedBox(width: 4),
              Text(
                formatCount(count),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colour,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin bar: kept in green, then deleted in red, then what's left.
class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.keptShare,
    required this.deletedShare,
    required this.keepColor,
    required this.deleteColor,
    required this.trackColor,
  });

  final double keptShare;
  final double deletedShare;
  final Color keepColor;
  final Color deleteColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: trackColor)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * keptShare,
                  child: ColoredBox(color: keepColor),
                ),
                Positioned(
                  left: width * keptShare,
                  top: 0,
                  bottom: 0,
                  width: width * deletedShare,
                  child: ColoredBox(color: deleteColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
