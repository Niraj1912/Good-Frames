import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:good_frames/models/keep_side.dart';
import 'package:good_frames/theme/app_theme.dart';

/// Keep and Delete on the same sides as the swipe directions (Keep on the
/// right unless the user swapped them), with Undo and Later between them.
///
/// While a photo is dragged, the button it's heading for grows with the
/// drag, and Delete fills in solid red once letting go would delete. So the
/// buttons show what's about to happen without colouring the photo.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.onDelete,
    required this.onKeep,
    required this.onUndo,
    this.onLater,
    this.showUndo = true,
    this.keepSide = KeepSide.right,
    this.dragProgress,
    this.upProgress,
  });

  final KeepSide keepSide;

  final VoidCallback? onDelete;
  final VoidCallback? onKeep;

  /// Null when there's nothing to undo, which greys the button out.
  final VoidCallback? onUndo;

  /// Puts the photo off for later. Null hides the button, as in the zoomed
  /// photo viewer.
  final VoidCallback? onLater;

  /// False where undo makes no sense, such as the zoomed photo viewer.
  final bool showUndo;

  /// How far the photo is dragged, from -1 (left) to 1 (right), where 1 or
  /// -1 means letting go counts as a swipe. Null where nothing is dragged.
  final ValueListenable<double>? dragProgress;

  /// How far the photo is dragged up, from 0 to 1 (letting go puts it off).
  final ValueListenable<double>? upProgress;

  // Even, and a little tighter than Material's icon-button default, so the
  // labels fit beside Undo and Later on a 360-wide phone.
  static const _padding = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    final sideways = dragProgress;
    final up = upProgress;
    if (sideways == null && up == null) return _buttons(context, 0, 0);
    // Only the buttons rebuild as the drag moves, not the whole screen.
    return ListenableBuilder(
      listenable: Listenable.merge([sideways, up]),
      builder: (context, _) =>
          _buttons(context, sideways?.value ?? 0, up?.value ?? 0),
    );
  }

  Widget _buttons(BuildContext context, double progress, double upPull) {
    final colors = SortColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Dark text on a light green, light text on a dark one: always readable.
    final onKeepColor =
        ThemeData.estimateBrightnessForColor(colors.keep) == Brightness.dark
        ? Colors.white
        : Colors.black;

    // How strongly the photo is heading for each button, from 0 to 1.
    final towardsRight = progress.clamp(0.0, 1.0);
    final towardsLeft = (-progress).clamp(0.0, 1.0);
    final (keepPull, deletePull) = switch (keepSide) {
      KeepSide.right => (towardsRight, towardsLeft),
      KeepSide.left => (towardsLeft, towardsRight),
    };

    final deleteButton = Expanded(
      child: _Leaning(
        pull: deletePull,
        // Solid only once letting go would delete, and soft again if the
        // photo is pulled back. Switched with a short fade rather than
        // shaded in along the way, so the label never fades into the red.
        child: TweenAnimationBuilder(
          tween: Tween(end: deletePull >= 1 ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 150),
          builder: (context, fill, _) => FilledButton.icon(
            onPressed: onDelete,
            style: FilledButton.styleFrom(
              padding: _padding,
              // A soft red wash rather than a solid red at rest: deleting
              // is the weightier choice, so it's clear but doesn't shout.
              backgroundColor: Color.lerp(
                Color.alphaBlend(
                  colors.delete.withValues(alpha: 0.16),
                  scheme.surface,
                ),
                colors.delete,
                fill,
              ),
              // The delete red is the theme's error colour, so its text
              // colour is the one made to be read on it.
              foregroundColor: Color.lerp(colors.delete, scheme.onError, fill),
            ),
            icon: const Icon(Icons.close),
            label: const Text('Delete'),
          ),
        ),
      ),
    );
    final keepButton = Expanded(
      child: _Leaning(
        pull: keepPull,
        child: FilledButton.icon(
          onPressed: onKeep,
          style: FilledButton.styleFrom(
            padding: _padding,
            backgroundColor: colors.keep,
            foregroundColor: onKeepColor,
          ),
          icon: const Icon(Icons.check),
          label: const Text('Keep'),
        ),
      ),
    );
    final (left, right) = switch (keepSide) {
      KeepSide.right => (deleteButton, keepButton),
      KeepSide.left => (keepButton, deleteButton),
    };
    final middle = [
      if (showUndo)
        _SquareButton(onPressed: onUndo, icon: Icons.undo, tooltip: 'Undo'),
      if (onLater != null)
        _Leaning(
          pull: upPull,
          child: _SquareButton(
            onPressed: onLater,
            icon: Icons.schedule,
            tooltip: 'Decide later',
          ),
        ),
    ];

    return Row(
      children: [
        left,
        const SizedBox(width: 12),
        for (final (index, button) in middle.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          button,
        ],
        if (middle.isNotEmpty) const SizedBox(width: 12),
        right,
      ],
    );
  }
}

/// Undo and Later: outlined, so they read as smaller choices than Keep and
/// Delete. A little narrower than tall, leaving Keep and Delete room for
/// their labels on a small phone.
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      icon: Icon(icon),
      tooltip: tooltip,
    );
  }
}

/// Grows a button a little as the photo heads its way ([pull] from 0 to 1),
/// following the finger. The short animation smooths the jump back to its
/// size once the photo has gone.
class _Leaning extends StatelessWidget {
  const _Leaning({required this.pull, required this.child});

  final double pull;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: 1 + 0.06 * pull,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: child,
    );
  }
}
