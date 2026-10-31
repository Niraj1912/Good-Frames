import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          LinearProgressIndicator(value: total == 0 ? 0 : sorted / total),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$sorted / $total sorted',
                style: theme.textTheme.labelLarge,
              ),
              Text(
                'Keep $kept  ·  Delete $deleted',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
