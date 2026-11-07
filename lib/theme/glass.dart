import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The colours of the glass look: the background every screen sits on
/// (fields of colour on paper, or deep glows on near-black in dark mode),
/// and the panes of glass laid over it. Read them with
/// `GlassColors.of(context)`.
@immutable
class GlassColors extends ThemeExtension<GlassColors> {
  const GlassColors({
    required this.base,
    required this.blobs,
    required this.sheen,
    required this.fill,
    required this.shine,
    required this.overPhotos,
    required this.edge,
  });

  // Each colour is as vivid as it can be while the app's grey and blue
  // text still reads on it at 4.5:1 (the lightness decides that, so they
  // sit at the same lightness and differ in hue).
  static const light = GlassColors(
    base: Color(0xFFF7F6F3),
    blobs: [
      Color(0xFFFFCDB2), // Coral
      Color(0xFFBCDCFF), // Sky, near the accent blue
      Color(0xFF9EEBD3), // Teal
      Color(0xFFFFD877), // Amber
    ],
    sheen: Color(0x8CFFFFFF),
    fill: Color(0x40FFFFFF),
    shine: Color(0x40FFFFFF),
    overPhotos: Color(0xDBFFFFFF),
    edge: Color(0xE6FFFFFF),
  );

  // Deep shades at half strength, and only a faint shine, so the light
  // grey text still reads on the brightest part.
  static const dark = GlassColors(
    base: Color(0xFF131313),
    blobs: [
      Color(0x80712B13),
      Color(0x800C447C),
      Color(0x80085041),
      Color(0x80633806),
    ],
    sheen: Color(0x10FFFFFF),
    fill: Color(0x06FFFFFF),
    shine: Color(0x05FFFFFF),
    overPhotos: Color(0xE0131313),
    edge: Color(0x29FFFFFF),
  );

  /// The paper (or near-black) under everything.
  final Color base;

  /// The fields of colour on it, one near each corner. They never move,
  /// so they're painted once.
  final List<Color> blobs;

  /// A pane's colour at its top, where light catches it...
  final Color sheen;

  /// ...fading to this at its bottom.
  final Color fill;

  /// Laid over a tinted pane's top, for the same catch of light.
  final Color shine;

  /// For glass that can have a photo behind it, such as a sheet over the
  /// sort screen. A photo can be any colour, so this hides more of it,
  /// keeping text on the glass readable.
  final Color overPhotos;

  /// The pane's edge at its top left, fading round to the bottom right,
  /// like the rim of a sheet of glass lit from above.
  final Color edge;

  static GlassColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GlassColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  GlassColors copyWith({
    Color? base,
    List<Color>? blobs,
    Color? sheen,
    Color? fill,
    Color? shine,
    Color? overPhotos,
    Color? edge,
  }) => GlassColors(
    base: base ?? this.base,
    blobs: blobs ?? this.blobs,
    sheen: sheen ?? this.sheen,
    fill: fill ?? this.fill,
    shine: shine ?? this.shine,
    overPhotos: overPhotos ?? this.overPhotos,
    edge: edge ?? this.edge,
  );

  @override
  GlassColors lerp(GlassColors? other, double t) {
    if (other == null) return this;
    return GlassColors(
      base: Color.lerp(base, other.base, t)!,
      blobs: [
        for (var i = 0; i < blobs.length; i++)
          Color.lerp(blobs[i], other.blobs[i], t)!,
      ],
      sheen: Color.lerp(sheen, other.sheen, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      shine: Color.lerp(shine, other.shine, t)!,
      overPhotos: Color.lerp(overPhotos, other.overPhotos, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
    );
  }
}

/// The background behind every screen. It sits under the app's navigator,
/// so it stays still while pages fade over it.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Its own layer, so it's drawn once rather than on every frame.
        RepaintBoundary(
          child: CustomPaint(painter: _Blobs(GlassColors.of(context))),
        ),
        child,
      ],
    );
  }
}

class _Blobs extends CustomPainter {
  const _Blobs(this.colors);

  final GlassColors colors;

  // Where each field sits, as shares of the screen, and how far it
  // spreads, as a share of the shorter side: coral top left, sky right,
  // amber left, teal bottom right.
  static const _places = [
    (x: 0.0, y: 0.02, spread: 0.85),
    (x: 1.0, y: 0.3, spread: 0.7),
    (x: 0.0, y: 0.72, spread: 0.75),
    (x: 1.0, y: 0.98, spread: 0.85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.base);
    for (var i = 0; i < colors.blobs.length; i++) {
      final place = _places[i % _places.length];
      final colour = colors.blobs[i];
      final centre = Offset(size.width * place.x, size.height * place.y);
      final radius = size.shortestSide * place.spread;
      // Strongest in the middle, fading to nothing at the edge.
      final paint = Paint()
        ..shader = RadialGradient(colors: [colour, colour.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: centre, radius: radius));
      canvas.drawCircle(centre, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_Blobs oldDelegate) => oldDelegate.colors != colors;
}

/// A pane of glass floating just above the bottom of the screen, holding a
/// screen's main buttons. Clear of the phone's gesture bar.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Glass(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}

/// A small capsule of glass holding a screen's top-right buttons together,
/// so they read as one control rather than loose icons.
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: const BorderRadius.all(Radius.circular(99)),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A pane of glass: milky, a little brighter at the top where light
/// catches it, with a rim that's brightest at the top left.
///
/// It doesn't blur what's behind unless asked ([blur]). Over the still,
/// already-soft background a blur would look the same, and blurring is one
/// of the heaviest things a phone can draw, every frame, so leaving it out
/// keeps the app smooth on older and cheaper phones too.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.tint,
    this.padding = EdgeInsets.zero,
    this.blur = false,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// A colour for the glass in place of the usual milky wash, such as an
  /// album cover's tint. Keep it partly see-through.
  final Color? tint;

  final EdgeInsetsGeometry padding;

  /// Blurs what's behind, for real. Only for glass that something detailed
  /// can be behind, such as a sheet over a photo.
  final bool blur;

  /// How strongly what's behind is blurred, when it is.
  static const blurSigma = 18.0;

  @override
  Widget build(BuildContext context) {
    final glass = GlassColors.of(context);
    final tint = this.tint;
    final pane = CustomPaint(
      foregroundPainter: _Rim(borderRadius, glass.edge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: tint == null
                ? [glass.sheen, glass.fill]
                : [Color.alphaBlend(glass.shine, tint), tint],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    // Clipped, so taps ripple within the rounded corners.
    return ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: pane,
            )
          : pane,
    );
  }
}

/// A pane's hairline rim: [colour] at the top left, fading to a third of it
/// at the bottom right.
class _Rim extends CustomPainter {
  const _Rim(this.borderRadius, this.colour);

  final BorderRadius borderRadius;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colour,
          colour.withValues(alpha: colour.a / 3),
        ],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect.deflate(0.5)), paint);
  }

  @override
  bool shouldRepaint(_Rim oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.borderRadius != borderRadius;
}
