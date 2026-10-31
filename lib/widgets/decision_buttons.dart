import 'package:flutter/material.dart';

/// Delete on the left and Keep on the right, the same sides as the swipe
/// directions, with Undo between them.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onDelete,
    required this.onKeep,
    required this.onUndo,
  });

  final VoidCallback? onDelete;
  final VoidCallback? onKeep;

  /// Null when there's nothing to undo, which greys the button out.
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const tall = Size.fromHeight(56);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onDelete,
            style: FilledButton.styleFrom(
              backgroundColor: colors.errorContainer,
              foregroundColor: colors.onErrorContainer,
              minimumSize: tall,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ),
        const SizedBox(width: 12),
        IconButton.outlined(
          onPressed: onUndo,
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onKeep,
            style: FilledButton.styleFrom(minimumSize: tall),
            icon: const Icon(Icons.favorite_outline),
            label: const Text('Keep'),
          ),
        ),
      ],
    );
  }
}
