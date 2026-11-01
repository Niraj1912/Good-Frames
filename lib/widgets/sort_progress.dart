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
          // Glides to each new value instead of jumping.
          TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : sorted / total),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: value),
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
