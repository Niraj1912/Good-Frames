import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:good_frames/models/keep_side.dart';

/// Which way a card was swiped. Left and right decide; up is for later.
enum SwipeDirection { left, right, up }

/// A card the user drags left, right or up. Let go past the threshold, or
/// flick it, and it flies off screen and reports the direction. Otherwise it
/// springs back to the middle. A drag counts in whichever direction it has
/// moved furthest, so a slightly crooked swipe still does what it looks like.
///
/// Buttons and keys swipe it through [SwipeCardState.swipe], so every way of
/// deciding looks the same.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.cardId,
    required this.onSwiped,
    required this.child,
    this.dragProgress,
    this.upProgress,
    this.enterFrom,
    this.onTap,
    this.keepSide = KeepSide.right,
    this.vibration = true,
  });

  /// Which way keeps, so dragging that way shows the keep colour.
  final KeepSide keepSide;

  /// Buzz softly when letting go would count, and when the card leaves.
  final bool vibration;

  /// Called on a tap (no drag), e.g. to open the photo for zooming.
  final VoidCallback? onTap;

  /// What the card is showing. When it changes, the card resets to the
  /// middle, ready for the next photo.
  final String cardId;

  final ValueChanged<SwipeDirection> onSwiped;

  /// The card's face, centred at its own size: a photo-shaped card can be
  /// smaller than the area. The whole area still catches drags, so a thin
  /// panorama is as easy to swipe as a tall portrait.
  final Widget child;

  /// Updated from -1 (dragged fully left) to 1 (fully right), so the card
  /// behind can react without rebuilding the whole screen. 0 while the drag
  /// is heading up.
  final ValueNotifier<double>? dragProgress;

  /// Updated from 0 to 1 (dragged up far enough to count), and 0 while the
  /// drag is heading left or right.
  final ValueNotifier<double>? upProgress;

  /// When a new [cardId] arrives, slide it in from this side instead of
  /// just appearing. Used for undo: the photo comes back the way it went.
  final SwipeDirection? enterFrom;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  // How far to drag, as a share of the card's width, before letting go
  // counts as a swipe. The same distance counts upwards too.
  static const _thresholdShare = 0.3;
  // A flick faster than this, in pixels per second, counts even if short.
  static const _flickSpeed = 1000.0;
  // Tilt at a full card width of drag, in radians (about 8 degrees).
  static const _maxTilt = 0.14;
  // Slightly springy: settles quickly with one small overshoot.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 32,
  );

  // Unbounded, because the spring overshoots past its target and back.
  late final AnimationController _animation = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onAnimate);

  Offset _offset = Offset.zero;
  Offset _animateFrom = Offset.zero;
  Offset _animateTo = Offset.zero;
  SwipeDirection? _leaving; // Set while flying off; ignores more input.
  SwipeDirection? _pendingEntry; // Waiting for a size to slide in from.
  bool _pastThreshold = false;
  Size _size = Size.zero;

  double get _threshold => math.max(_size.width * _thresholdShare, 1);

  @override
  void initState() {
    super.initState();
    _pendingEntry = widget.enterFrom;
  }

  @override
  void didUpdateWidget(SwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) {
      _animation.stop();
      _offset = Offset.zero;
      _leaving = null;
      _pastThreshold = false;
      _pendingEntry = widget.enterFrom;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  /// Swipes the card away in [direction], as if the user had dragged it.
  void swipe(SwipeDirection direction) {
    if (_leaving == null) _flyOut(direction);
  }

  /// Brings a swiped card back to the middle, e.g. when saving failed.
  void comeBack() {
    _leaving = null;
    _pastThreshold = false;
    _springBack();
  }

  void _onPanStart(DragStartDetails details) {
    if (_leaving == null) _animation.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_leaving != null) return;
    _setOffset(_offset + details.delta);

    final past = _heading(_offset) != null;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      // A small tick tells the thumb "let go now and it counts".
      if (past && widget.vibration) HapticFeedback.selectionClick();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_leaving != null) return;

    final velocity = details.velocity.pixelsPerSecond;
    final direction = _flick(velocity) ?? _heading(_offset);
    if (direction == null) {
      _springBack(velocity: velocity);
    } else {
      final speed = direction == SwipeDirection.up ? -velocity.dy : velocity.dx;
      _flyOut(direction, speed: speed.abs());
    }
  }

  // Up when the card has moved up more than sideways; otherwise left or
  // right. Null if it hasn't gone far enough that way to count.
  SwipeDirection? _heading(Offset offset) {
    if (_isUp(offset)) {
      return -offset.dy > _threshold ? SwipeDirection.up : null;
    }
    if (offset.dx.abs() <= _threshold) return null;
    return offset.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
  }

  // A fast flick counts even if short, again in its main direction.
  SwipeDirection? _flick(Offset velocity) {
    if (_isUp(velocity)) {
      return -velocity.dy > _flickSpeed ? SwipeDirection.up : null;
    }
    if (velocity.dx.abs() <= _flickSpeed) return null;
    return velocity.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
  }

  static bool _isUp(Offset offset) => -offset.dy > offset.dx.abs();

  // Leaves at the speed of the flick, so the card feels thrown rather than
  // played back. Buttons and keys (no speed) use a brisk default.
  void _flyOut(SwipeDirection direction, {double speed = 0}) {
    _leaving = direction;
    if (widget.vibration) HapticFeedback.mediumImpact();
    // Far enough that even the tilted corner ends up off screen.
    final target = switch (direction) {
      SwipeDirection.right => Offset(_size.width * 1.4, _offset.dy),
      SwipeDirection.left => Offset(-_size.width * 1.4, _offset.dy),
      SwipeDirection.up => Offset(_offset.dx, -_size.height * 1.4),
    };
    final distance = (target - _offset).distance;
    final seconds = (distance / math.max(speed, 2400)).clamp(0.12, 0.28);

    _animateFrom = _offset;
    _animateTo = target;
    _animation.value = 0;
    _animation
        .animateTo(
          1,
          duration: Duration(milliseconds: (seconds * 1000).round()),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          widget.dragProgress?.value = 0;
          widget.upProgress?.value = 0;
          widget.onSwiped(direction);
        });
  }

  // A real spring, carrying on with the finger's speed: the card overshoots
  // the middle a little and settles, like something with weight.
  void _springBack({Offset velocity = Offset.zero}) {
    _animateFrom = _offset;
    _animateTo = Offset.zero;
    final distance = _offset.distance;
    // The spring runs from 0 to 1, so turn the finger's speed into how much
    // of the way back to the middle it covers each second.
    final towardsMiddle = distance == 0
        ? 0.0
        : -(velocity.dx * _offset.dx + velocity.dy * _offset.dy) / distance;
    final startSpeed = distance == 0 ? 0.0 : towardsMiddle / distance;
    // snapToEnd: a spring only gets "close enough", so finish exactly.
    _animation.animateWith(
      SpringSimulation(_spring, 0, 1, startSpeed, snapToEnd: true),
    );
  }

  void _slideIn(SwipeDirection from) {
    _offset = switch (from) {
      SwipeDirection.right => Offset(_size.width * 1.2, 0),
      SwipeDirection.left => Offset(-_size.width * 1.2, 0),
      SwipeDirection.up => Offset(0, -_size.height * 1.2),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateFrom = _offset;
      _animateTo = Offset.zero;
      _animation.value = 0;
      _animation.animateTo(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onAnimate() {
    _setOffset(Offset.lerp(_animateFrom, _animateTo, _animation.value)!);
  }

  void _setOffset(Offset offset) {
    setState(() => _offset = offset);
    final (sideways, up) = _progress(offset);
    widget.dragProgress?.value = sideways;
    widget.upProgress?.value = up;
  }

  // How far towards counting the card has moved: sideways (-1 to 1) or up
  // (0 to 1). Only the main direction shows, so the stamps and buttons
  // always say what letting go would do.
  (double, double) _progress(Offset offset) => _isUp(offset)
      ? (0.0, (-offset.dy / _threshold).clamp(0.0, 1.0))
      : ((offset.dx / _threshold).clamp(-1.0, 1.0), 0.0);

  @override
  Widget build(BuildContext context) {
    // Grey: putting off isn't keep or delete.
    const later = Color(0xFF9AA7B2);
    // Brighter than the text colours: these sit on photos.
    const keep = (
      label: 'KEEP',
      color: Color(0xFF34D399),
      icon: Icons.check_rounded,
    );
    const delete = (
      label: 'DELETE',
      color: Color(0xFFFF5A6A),
      icon: Icons.close_rounded,
    );
    // Each stamp sits on the side the card is leaving from, like a label
    // being revealed: dragging right shows the top-left one.
    final (right, left) = switch (widget.keepSide) {
      KeepSide.right => (keep, delete),
      KeepSide.left => (delete, keep),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        // Start off screen on the first frame, then slide in, so the card
        // never flashes in the middle first.
        if (_pendingEntry case final from?) {
          _pendingEntry = null;
          _slideIn(from);
        }
        final (progress, up) = _progress(_offset);
        final tilt =
            _maxTilt * (_offset.dx / math.max(_size.width, 1)).clamp(-1.0, 1.0);

        return GestureDetector(
          // Catch drags anywhere in the area, not just on the card itself.
          behavior: HitTestBehavior.opaque,
          // A tap and a drag can't be confused: the drag only starts once
          // the finger has moved, and the tap only fires if it didn't.
          onTap: _leaving == null ? widget.onTap : null,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Transform.translate(
            offset: _offset,
            child: Center(
              child: Transform.rotate(
                angle: tilt,
                // Pivot near the bottom, like a card held at its base.
                alignment: const Alignment(0, 0.8),
                // Sized by the face, so the stamps sit on its corners. Not
                // clipped, so a stamp can stick out of a very thin panorama.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    widget.child,
                    // Colour washes in from the corner the card is heading
                    // for, about half way across: green to keep, red to
                    // delete, grey to put off.
                    Positioned.fill(
                      child: SwipeWash(
                        label: right.label,
                        color: right.color,
                        icon: right.icon,
                        from: Alignment.topRight,
                        strength: progress.clamp(0.0, 1.0),
                      ),
                    ),
                    Positioned.fill(
                      child: SwipeWash(
                        label: left.label,
                        color: left.color,
                        icon: left.icon,
                        from: Alignment.topLeft,
                        strength: (-progress).clamp(0.0, 1.0),
                      ),
                    ),
                    Positioned.fill(
                      child: SwipeWash(
                        label: 'LATER',
                        color: later,
                        from: Alignment.topCenter,
                        strength: up,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What shows while dragging: a soft round bloom of [color] spilling in
/// from the corner the card is heading for, blended into the photo so its
/// detail still shows, and (with a [word]) a pill of frosted glass holding
/// an icon and the word. [strength] runs from 0 (hidden) to 1 (past the
/// threshold).
@visibleForTesting
class SwipeWash extends StatelessWidget {
  SwipeWash({
    required this.label,
    required this.color,
    required this.from,
    required this.strength,
    this.icon,
  }) : super(key: ValueKey(label));

  final String label;
  final Color color;
  final Alignment from;
  final double strength;

  /// Set to show the glass pill; without it, only the bloom shows.
  final IconData? icon;

  /// Fully bright by half way to the threshold, so it never looks faint.
  double get opacity => (strength * 2).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _BloomPainter(color, from, opacity)),
          if (icon != null)
            Align(
              alignment: Alignment(from.x * 0.9, -0.9),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: 1.12 - 0.12 * strength,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x66101820),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0x59FFFFFF)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 18, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A radial bloom from a corner or edge, easing out to nothing. Drawn with
/// over a dark pool, so it looks the same on any photo.
class _BloomPainter extends CustomPainter {
  const _BloomPainter(this.color, this.from, this.opacity);

  final Color color;
  final Alignment from;
  final double opacity;

  // Many small steps along a smooth curve, so the eye finds no ring where
  // the colour changes pace.
  static const _steps = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= _steps; i++) {
      final t = i / _steps;
      colors.add(color.withValues(alpha: opacity * 0.9 * (1 - _ease(t))));
      stops.add(t);
    }
    final rect = Offset.zero & size;
    // A soft dark pool under the colour first, so the colour looks the same
    // on a white sky as on a black night, and the pill's white reads on it.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: from,
          radius: 1.3,
          colors: [
            for (var i = 0; i <= _steps; i++)
              Colors.black.withValues(
                alpha: opacity * 0.5 * (1 - _ease(i / _steps)),
              ),
          ],
          stops: [for (var i = 0; i <= _steps; i++) i / _steps],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: from,
          radius: 1.15,
          colors: colors,
          stops: stops,
        ).createShader(rect),
    );
  }

  static double _ease(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  @override
  bool shouldRepaint(_BloomPainter old) =>
      old.color != color || old.from != from || old.opacity != opacity;
}
