import 'package:flutter/material.dart';
import 'package:photo_swipe/models/keep_side.dart';
import 'package:photo_swipe/theme/app_theme.dart';

/// Keep and Delete on the same sides as the swipe directions (Keep on the
/// right unless the user swapped them), with Undo between them.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onDelete,
    required this.onKeep,
    required this.onUndo,
    this.showUndo = true,
    this.keepSide = KeepSide.right,
  });

  final KeepSide keepSide;

  final VoidCallback? onDelete;
  final VoidCallback? onKeep;

  /// Null when there's nothing to undo, which greys the button out.
  final VoidCallback? onUndo;

  /// False where undo makes no sense, such as the zoomed photo viewer.
  final bool showUndo;

  @override
  Widget build(BuildContext context) {
    final colors = SortColors.of(context);
    final surface = Theme.of(context).colorScheme.surface;
    // Dark text on a light green, light text on a dark one: always readable.
    final onKeepColor =
        ThemeData.estimateBrightnessForColor(colors.keep) == Brightness.dark
        ? Colors.white
        : Colors.black;

    final deleteButton = Expanded(
      // A soft red wash rather than a solid red: deleting is the
      // weightier choice, so it's clear but doesn't shout.
      child: FilledButton.icon(
        onPressed: onDelete,
        style: FilledButton.styleFrom(
          backgroundColor: Color.alphaBlend(
            colors.delete.withValues(alpha: 0.16),
            surface,
          ),
          foregroundColor: colors.delete,
        ),
        icon: const Icon(Icons.close),
        label: const Text('Delete'),
      ),
    );
    final keepButton = Expanded(
      child: FilledButton.icon(
        onPressed: onKeep,
        style: FilledButton.styleFrom(
          backgroundColor: colors.keep,
          foregroundColor: onKeepColor,
        ),
        icon: const Icon(Icons.check),
        label: const Text('Keep'),
      ),
    );
    final (left, right) = switch (keepSide) {
      KeepSide.right => (deleteButton, keepButton),
      KeepSide.left => (keepButton, deleteButton),
    };

    return Row(
      children: [
        left,
        if (showUndo) ...[
          const SizedBox(width: 12),
          IconButton.outlined(
            onPressed: onUndo,
            style: IconButton.styleFrom(
              minimumSize: const Size(52, 52),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
        ],
        const SizedBox(width: 12),
        right,
      ],
    );
  }
}
