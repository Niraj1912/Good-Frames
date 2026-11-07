import 'package:flutter/material.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/grease_mark.dart';

/// One frame on the strip.
typedef StripFrame = ({
  Photo photo,

  /// Its place in the album, counting from 1.
  int number,
  Decision? decision,
  bool isCurrent,
});

/// Where the user is in the album, as a strip of film: a few photos already
/// sorted, each marked with a grease-pencil circle (kept) or cross (deleted),
/// the one being sorted lit up, and the next ones waiting dim. Under it, the
/// count so far.
///
/// Dark in both themes, like real film, so the marks and amber frame numbers
/// read the same on any background.
class FilmStrip extends StatelessWidget {
  const FilmStrip({
    super.key,
    required this.frames,
    required this.imageFor,
    required this.sorted,
    required this.total,
    required this.kept,
    required this.deleted,
    this.later = 0,
  });

  final List<StripFrame> frames;

  /// A small copy of a frame's photo.
  final ImageProvider Function(Photo photo) imageFor;

  final int sorted;
  final int total;
  final int kept;
  final int deleted;

  /// Photos put off for later, still waiting to come back.
  final int later;

  // Light on the dark strip: brighter than the app's keep and delete colours,
  // which are tuned for pale glass.
  static const keepOnFilm = Color(0xFF6FD49A);
  static const deleteOnFilm = Color(0xFFFF7A68);
  static const amber = Color(0xFFF2A33A);
  static const _film = Color(0xCC121315);

  @override
  Widget build(BuildContext context) {
    final tally = AppTheme.edgePrint.copyWith(fontSize: 17);
    final quiet = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.white70,
      fontFeatures: AppTheme.tabularFigures,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _film,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: CustomPaint(
          painter: const _Sprockets(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scales down rather than overflowing on a narrow phone.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, frame) in frames.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        _Frame(
                          // The same photo keeps its widget as the strip
                          // moves along, so it can grow and draw its mark.
                          key: ValueKey(frame.photo.id),
                          frame: frame,
                          image: imageFor(frame.photo),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // A Wrap, not a Row: with large text the tally moves onto a
                // second line instead of running off the screen.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${formatCount(sorted)} / ${formatCount(total)} sorted',
                      style: quiet,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Tally(
                          label: 'Keep',
                          count: kept,
                          icon: Icons.check,
                          colour: keepOnFilm,
                          style: tally,
                        ),
                        const SizedBox(width: 12),
                        _Tally(
                          label: 'Delete',
                          count: deleted,
                          icon: Icons.close,
                          colour: deleteOnFilm,
                          style: tally,
                        ),
                        if (later > 0) ...[
                          const SizedBox(width: 12),
                          _Tally(
                            label: 'Later',
                            count: later,
                            icon: Icons.schedule,
                            colour: Colors.white70,
                            style: tally,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.frame, required this.image});

  final StripFrame frame;
  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    final decision = frame.decision;
    final current = frame.isCurrent;
    final width = current ? 50.0 : 38.0;
    final height = current ? 66.0 : 50.0;
    // Sorted ones are a little faded, waiting ones more so, the current one
    // not at all.
    final opacity = current ? 1.0 : (decision == null ? 0.45 : 0.75);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Grows when the frame becomes the current one, and shrinks back
        // once it's sorted.
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: current ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: opacity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(current ? 3 : 4),
                  child: Image(
                    image: image,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: Color(0xFF2A2B2E)),
                  ),
                ),
              ),
              if (decision != null)
                Positioned(
                  left: -3,
                  top: -3,
                  right: -3,
                  bottom: -3,
                  // Drawn in as soon as the photo is sorted.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    builder: (context, progress, _) => GreaseMark(
                      decision: decision,
                      progress: progress,
                      colour: decision == Decision.keep
                          ? FilmStrip.keepOnFilm
                          : FilmStrip.deleteOnFilm,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${frame.number}',
          style: AppTheme.edgePrint.copyWith(
            fontSize: 12,
            color: current ? Colors.white : FilmStrip.amber,
          ),
        ),
      ],
    );
  }
}

/// A count in the strip's own type, with the same icon as its button. Read
/// out as one phrase, such as "Keep 12".
class _Tally extends StatelessWidget {
  const _Tally({
    required this.label,
    required this.count,
    required this.icon,
    required this.colour,
    required this.style,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color colour;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label ${formatCount(count)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 3),
          Text(formatCount(count), style: style.copyWith(color: colour)),
        ],
      ),
    );
  }
}

/// The small holes along a film's top and bottom edges.
class _Sprockets extends CustomPainter {
  const _Sprockets();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x66FFFFFF);
    const holeWidth = 7.0;
    const pitch = 14.0;
    // Centred, so the pattern is the same at both ends.
    final count = (size.width / pitch).floor();
    final start = (size.width - (count * pitch - (pitch - holeWidth))) / 2;
    for (var i = 0; i < count; i++) {
      final x = start + i * pitch;
      for (final y in [4.0, size.height - 9]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, holeWidth, 5),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Sprockets old) => false;
}
