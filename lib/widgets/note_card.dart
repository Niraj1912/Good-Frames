import 'package:flutter/material.dart';
import 'package:good_frames/theme/glass.dart';

/// A short explanation at the top of a screen, on glass tinted with
/// [colour] and an icon to match, so it reads as a note rather than as fine
/// print.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.icon,
    required this.text,
    required this.colour,
  });

  final IconData icon;
  final String text;

  /// What the note is about: the delete colour on the Review screen, say.
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Glass(
      tint: Color.alphaBlend(
        colour.withValues(alpha: 0.08),
        GlassColors.of(context).fill,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 20, color: colour),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              // Lines the first line of text up with the icon's middle.
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
