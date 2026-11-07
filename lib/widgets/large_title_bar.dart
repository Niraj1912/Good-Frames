import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/glass.dart';

/// A screen's title the way an iPhone does it: big and bold at the top of the
/// list, then, as the list scrolls up, shrinking into a small centred title
/// on a blurred glass bar that stays put. Put it first in a
/// [CustomScrollView]'s slivers.
///
/// The blur only appears once the list has scrolled under it, which is the
/// one time something detailed (album covers, say) is behind it. At rest
/// nothing is blurred, so it costs nothing.
class LargeTitleBar extends StatelessWidget {
  const LargeTitleBar({super.key, required this.title, this.actions});

  final String title;

  /// Buttons for the top right, usually IconButtons. They're grouped in a
  /// glass capsule.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SliverPersistentHeader(
      pinned: true,
      delegate: _Delegate(
        title: title,
        actions: actions,
        topInset: MediaQuery.paddingOf(context).top,
        // Taller with large text, so the title never gets cut.
        largeHeight: scaler.scale(44).clamp(44, 88) + 12,
        canGoBack: Navigator.canPop(context),
      ),
    );
  }
}

class _Delegate extends SliverPersistentHeaderDelegate {
  const _Delegate({
    required this.title,
    required this.actions,
    required this.topInset,
    required this.largeHeight,
    required this.canGoBack,
  });

  final String title;
  final List<Widget>? actions;
  final double topInset;
  final double largeHeight;
  final bool canGoBack;

  static const _toolbar = 56.0;

  @override
  double get minExtent => topInset + _toolbar;

  @override
  double get maxExtent => topInset + _toolbar + largeHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);
    // 0 while the big title shows, 1 once it has shrunk into the bar.
    final collapse = (shrinkOffset / largeHeight).clamp(0.0, 1.0);
    final glass = GlassColors.of(context);
    final actions = this.actions;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The bar's own glass, fading in as content slides under it.
        if (collapse > 0)
          Opacity(
            opacity: collapse,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: Glass.blurSigma,
                  sigmaY: Glass.blurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: glass.base.withValues(alpha: 0.62),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: topInset,
          left: 0,
          right: 0,
          height: _toolbar,
          child: Row(
            children: [
              const SizedBox(width: 4),
              if (canGoBack) const BackButton(),
              Expanded(
                child: collapse < 0.7
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: ((collapse - 0.7) / 0.3).clamp(0.0, 1.0),
                        child: Text(
                          title,
                          style: theme.appBarTheme.titleTextStyle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              if (actions != null)
                GlassCapsule(children: actions)
              else if (canGoBack)
                const SizedBox(width: 48),
              const SizedBox(width: 12),
            ],
          ),
        ),
        // The big title, sliding up and fading as the list scrolls.
        if (collapse < 0.7)
          Positioned(
            left: 20,
            right: 20,
            bottom: 8,
            child: Opacity(
              opacity: 1 - collapse / 0.7,
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 34,
                    letterSpacing: -1.1,
                    height: 1.15,
                    // The font's large-size drawing, finer at 34 points.
                    fontVariations: const [FontVariation('opsz', 96)],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(_Delegate old) =>
      title != old.title ||
      topInset != old.topInset ||
      largeHeight != old.largeHeight ||
      canGoBack != old.canGoBack ||
      actions != old.actions;
}
