import 'package:flutter/material.dart';
import 'package:good_frames/theme/glass.dart';

/// Placeholders shaped like the content that is on its way, with a soft
/// highlight sweeping across them. They replace spinners: the screen holds
/// its layout while it loads, so nothing jumps when the real content lands.
///
/// Wrap a group of [SkeletonBox]es in one [Shimmer] so they share a single
/// animation and the highlight sweeps across them in step.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  /// The sweep's [Animation], for the boxes below to paint with.
  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // People who turned animations off in system settings get still shapes.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A screen reader says "loading" once, not once per grey box.
    return Semantics(
      label: 'Loading',
      container: true,
      child: ExcludeSemantics(
        child: _ShimmerScope(animation: _controller, child: widget.child),
      ),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => animation != old.animation;
}

/// One grey placeholder shape. Give it a size, or let a parent do.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.circle = false,
    this.onDark = false,
  });

  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  /// For sitting on a dark surface (the film strip) in either theme.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0x14FFFFFF) : const Color(0x14000000);
    final glint = dark ? const Color(0x29FFFFFF) : const Color(0x0FFFFFFF);
    final animation = Shimmer.maybeOf(context);

    Widget box(double t) => DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        gradient: animation == null
            ? null
            : LinearGradient(
                // The bright band travels from off the left edge to off the
                // right one.
                begin: Alignment(-1.5 + 3 * t, -0.3),
                end: Alignment(-0.5 + 3 * t, 0.3),
                colors: [base, Color.alphaBlend(glint, base), base],
              ),
        color: animation == null ? base : null,
      ),
    );

    return SizedBox(
      width: width,
      height: height,
      child: animation == null
          ? box(0)
          : AnimatedBuilder(
              animation: animation,
              builder: (context, _) => box(animation.value),
            ),
    );
  }
}

/// The sort screen while photos load, laid out like the real thing: the
/// photo card, the count under it, and the pane of glass with Undo and the
/// swipe hints.
class SortSkeleton extends StatelessWidget {
  const SortSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox.expand(child: SkeletonBox(radius: 16)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SkeletonBox(width: 90, height: 12),
          ),
          // Undo and the swipe hint, on glass.
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Glass(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SkeletonBox(width: 48, height: 48, circle: true),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 30, radius: 24)),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBox(height: 30, radius: 24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The albums screen while it loads: the "pick up where you stopped" card
/// (a full-bleed cover with a glass pane), then the glass list of albums,
/// each with a cover, a name and a count.
class AlbumListSkeleton extends StatelessWidget {
  const AlbumListSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The "pick up" card: a full-bleed cover with a glass pane on it.
            const SizedBox(
              height: 264,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SkeletonBox(radius: 28),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Glass(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(width: 130, height: 11),
                                SizedBox(height: 8),
                                SkeletonBox(width: 110, height: 20),
                                SizedBox(height: 8),
                                SkeletonBox(width: 150, height: 11),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                          SkeletonBox(width: 88, height: 40, radius: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 0, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 90, height: 12),
              ),
            ),
            Glass(
              child: Column(
                children: [
                  for (var i = 0; i < rows; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: 82,
                        color: divider,
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 10, 16, 10),
                      child: Row(
                        children: [
                          SkeletonBox(width: 60, height: 60, radius: 14),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(width: 140, height: 14),
                                SizedBox(height: 8),
                                SkeletonBox(width: 80, height: 11),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grid of photo squares, for the trash.
class PhotoGridSkeleton extends StatelessWidget {
  const PhotoGridSkeleton({super.key, this.tiles = 12});

  final int tiles;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 0; i < tiles; i++) const SkeletonBox(radius: 12),
        ],
      ),
    );
  }
}

/// A few list rows with an icon, a title and a subtitle, for the folders
/// list.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          Glass(
            child: Column(
              children: [
                for (var i = 0; i < rows; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        SkeletonBox(width: 28, height: 28, radius: 8),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 120, height: 14),
                              SizedBox(height: 8),
                              SkeletonBox(height: 11),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
