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
  });

  final int sorted;
  final int total;
  final int kept;
  final int deleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SortColors.of(context);
    final counts = theme.textTheme.labelLarge?.copyWith(
      fontFeatures: AppTheme.tabularFigures,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
          const SizedBox(height: 8),
          // A Wrap, not a Row: with large text on a small phone the counts
          // move onto a second line instead of running off the screen.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                '${formatCount(sorted)} / ${formatCount(total)} sorted',
                style: counts,
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Keep ${formatCount(kept)}',
                      style: TextStyle(color: colors.keep),
                    ),
                    TextSpan(
                      text: '  ·  ',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: 'Delete ${formatCount(deleted)}',
                      style: TextStyle(color: colors.delete),
                    ),
                  ],
                ),
                style: counts,
              ),
            ],
          ),
        ],
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
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
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
