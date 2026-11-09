import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:good_frames/models/keep_side.dart';
import 'package:good_frames/theme/app_theme.dart';

/// The one row under the photo: a round Undo button, and three cues that say
/// which way to swipe for what, each a small glass badge with an arrow.
/// Keep and Delete follow [keepSide], so each badge sits on the side its
/// swipe really goes.
///
/// While the photo is dragged, the cue it is heading for swells, and fills
/// in solid once letting go would count. So the row doubles as the preview
/// of what's about to happen, without colouring the photo itself.
class SwipeHint extends StatelessWidget {
  const SwipeHint({
    super.key,
    required this.keepSide,
    required this.onUndo,
    required this.onLeft,
    required this.onUp,
    required this.onRight,
    this.dragProgress,
    this.upProgress,
  });

  final KeepSide keepSide;

  /// Null when there's nothing to undo, which greys the button out.
  final VoidCallback? onUndo;

  /// Tapping a cue does what swiping that way does. They are screen
  /// directions: which one keeps and which deletes is [keepSide]'s business.
  final VoidCallback onLeft;
  final VoidCallback onUp;
  final VoidCallback onRight;

  /// How far the photo is dragged sideways, from -1 (left) to 1 (right),
  /// where 1 or -1 means letting go counts as a swipe.
  final ValueListenable<double>? dragProgress;

  /// How far the photo is dragged up, from 0 to 1.
  final ValueListenable<double>? upProgress;

  @override
  Widget build(BuildContext context) {
    final sideways = dragProgress;
    final up = upProgress;
    if (sideways == null && up == null) return _row(context, 0, 0);
    // Only this row rebuilds as the drag moves, not the whole screen.
    return ListenableBuilder(
      listenable: Listenable.merge([sideways, up]),
      builder: (context, _) =>
          _row(context, sideways?.value ?? 0, up?.value ?? 0),
    );
  }

  Widget _row(BuildContext context, double progress, double upPull) {
    final colors = SortColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    final keep = (label: 'Keep', color: colors.keep);
    final delete = (label: 'Delete', color: colors.delete);
    final (left, right) = switch (keepSide) {
      KeepSide.right => (delete, keep),
      KeepSide.left => (keep, delete),
    };

    return Row(
      children: [
        _UndoButton(onPressed: onUndo),
        const SizedBox(width: 12),
        Expanded(
          // Shrinks a little rather than wrapping on a narrow phone or with
          // large text.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Cue(
                  icon: Icons.arrow_back_rounded,
                  label: left.label,
                  color: left.color,
                  pull: (-progress).clamp(0.0, 1.0),
                  iconFirst: true,
                  hint: 'swipe left',
                  onTap: onLeft,
                ),
                _Cue(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Later',
                  color: scheme.onSurfaceVariant,
                  pull: upPull.clamp(0.0, 1.0),
                  iconFirst: true,
                  hint: 'swipe up',
                  onTap: onUp,
                ),
                _Cue(
                  icon: Icons.arrow_forward_rounded,
                  label: right.label,
                  color: right.color,
                  pull: progress.clamp(0.0, 1.0),
                  iconFirst: false,
                  hint: 'swipe right',
                  onTap: onRight,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A round button of frosted glass, like the zoom magnifier on the photo.
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Undo',
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        fixedSize: const Size(48, 48),
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.04),
        foregroundColor: scheme.onSurface,
        side: BorderSide(
          color: scheme.onSurface.withValues(alpha: enabled ? 0.16 : 0.08),
        ),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.undo_rounded),
    );
  }
}

/// One swipe direction: a round badge with an arrow, and its word beside
/// it, the arrow on the outer edge. [pull] (0 to 1) is how far the photo is
/// heading this way: the badge grows, then fills solid once it counts.
class _Cue extends StatelessWidget {
  const _Cue({
    required this.icon,
    required this.label,
    required this.color,
    required this.pull,
    required this.iconFirst,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final double pull;
  final bool iconFirst;

  /// How it's announced, such as "swipe left".
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2);
    final solid = pull >= 1;
    // Dark arrow on a light fill, light on a dark one: always readable.
    final onSolid =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solid ? color : color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: solid ? 0 : 0.38)),
      ),
      child: Icon(icon, size: 18, color: solid ? onSolid : color),
    );
    final text = Text(label, style: style?.copyWith(color: color));

    return Semantics(
      button: true,
      label: '$label, $hint',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          // Tall enough to tap comfortably, with the cues close together.
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: AnimatedScale(
            scale: 1 + 0.12 * pull,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconFirst) ...[badge, const SizedBox(width: 8), text],
                if (!iconFirst) ...[text, const SizedBox(width: 8), badge],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
