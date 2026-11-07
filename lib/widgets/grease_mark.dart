import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:photo_swipe/models/decision.dart';

/// A mark drawn by hand, as a photographer marks a contact sheet with a
/// grease pencil: a loose circle round a photo to keep, a cross through one
/// to delete. When [progress] runs from 0 to 1 the pencil draws it.
class GreaseMark extends StatelessWidget {
  const GreaseMark({
    super.key,
    required this.decision,
    required this.colour,
    this.progress = 1,
    this.strokeWidth = 2.4,
  });

  final Decision decision;
  final Color colour;

  /// How much of the stroke is drawn so far, 0 to 1.
  final double progress;

  /// In logical pixels, whatever size the mark is drawn at.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MarkPainter(decision, colour, progress, strokeWidth),
    // Fills its parent.
    child: const SizedBox.expand(),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.decision, this.colour, this.progress, this.width);

  final Decision decision;
  final Color colour;
  final double progress;
  final double width;

  // Drawn in a 40 by 40 box, a little uneven on purpose: it should look like
  // a hand did it, not a shape tool.
  static Path get _circle => Path()
    ..moveTo(21, 4)
    ..cubicTo(31, 3, 37, 12, 36, 21)
    ..cubicTo(35, 30, 28, 37, 18, 36)
    ..cubicTo(8, 35, 3, 28, 4, 18)
    ..cubicTo(5, 8, 11, 5, 25, 6);

  static Path get _cross => Path()
    ..moveTo(6, 6)
    ..cubicTo(14, 15, 26, 26, 34, 34)
    ..moveTo(34, 6)
    ..cubicTo(26, 14, 14, 26, 6, 34);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final scale = size.shortestSide / 40;
    final source = decision == Decision.keep ? _circle : _cross;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width / scale
      ..color = colour;
    canvas.translate(
      (size.width - size.shortestSide) / 2,
      (size.height - size.shortestSide) / 2,
    );
    canvas.scale(scale);
    if (progress >= 1) {
      canvas.drawPath(source, paint);
      return;
    }
    // Each stroke is drawn up to the same share of its own length.
    for (final PathMetric metric in source.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.decision != decision ||
      old.colour != colour ||
      old.progress != progress ||
      old.width != width;
}
