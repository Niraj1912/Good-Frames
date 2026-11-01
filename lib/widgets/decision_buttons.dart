import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/app_theme.dart';

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
    final colors = SortColors.of(context);
    // Dark text on a light green, light text on a dark one: always readable.
    final onKeep =
        ThemeData.estimateBrightnessForColor(colors.keep) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.delete,
              side: BorderSide(color: colors.delete, width: 1.5),
            ),
            icon: const Icon(Icons.close),
            label: const Text('Delete'),
          ),
        ),
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
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: this.onKeep,
            style: FilledButton.styleFrom(
              backgroundColor: colors.keep,
              foregroundColor: onKeep,
            ),
            icon: const Icon(Icons.check),
            label: const Text('Keep'),
          ),
        ),
      ],
    );
  }
}
