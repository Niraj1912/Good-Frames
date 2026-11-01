import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/theme/app_theme.dart';

/// Which way a card was swiped.
enum SwipeDirection { left, right }

/// A card the user drags left or right. Let go past the threshold, or flick
/// it, and it flies off screen and reports the direction. Otherwise it
/// springs back to the middle.
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
    this.enterFrom,
  });

  /// What the card is showing. When it changes, the card resets to the
  /// middle, ready for the next photo.
  final String cardId;

  final ValueChanged<SwipeDirection> onSwiped;
  final Widget child;

  /// Updated from -1 (dragged fully left) to 1 (fully right), so the card
  /// behind can react without rebuilding the whole screen.
  final ValueNotifier<double>? dragProgress;

  /// When a new [cardId] arrives, slide it in from this side instead of
  /// just appearing. Used for undo: the photo comes back the way it went.
  final SwipeDirection? enterFrom;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  // How far to drag, as a share of the card's width, before letting go
  // counts as a swipe.
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

    final past = _offset.dx.abs() > _threshold;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      // A small tick tells the thumb "let go now and it counts".
      if (past) HapticFeedback.selectionClick();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_leaving != null) return;

    final velocity = details.velocity.pixelsPerSecond;
    final SwipeDirection? direction;
    if (velocity.dx.abs() > _flickSpeed) {
      direction = velocity.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else if (_offset.dx.abs() > _threshold) {
      direction = _offset.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else {
      direction = null;
    }

    if (direction == null) {
      _springBack(velocity: velocity);
    } else {
      _flyOut(direction, speed: velocity.dx.abs());
    }
  }

  // Leaves at the speed of the flick, so the card feels thrown rather than
  // played back. Buttons and keys (no speed) use a brisk default.
  void _flyOut(SwipeDirection direction, {double speed = 0}) {
    _leaving = direction;
    HapticFeedback.mediumImpact();
    final sign = direction == SwipeDirection.right ? 1.0 : -1.0;
    // Far enough that even the tilted corner ends up off screen.
    final target = Offset(sign * _size.width * 1.4, _offset.dy);
    final distance = (target.dx - _offset.dx).abs();
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
          widget.onSwiped(direction);
        });
  }

  // A real spring, carrying on with the finger's speed: the card overshoots
  // the middle a little and settles, like something with weight.
  void _springBack({Offset velocity = Offset.zero}) {
    _animateFrom = _offset;
    _animateTo = Offset.zero;
    final distance = _offset.distance;
    // The spring runs from 0 to 1, so scale the finger's speed to match.
    final startSpeed = distance == 0 ? 0.0 : -velocity.dx / distance;
    // snapToEnd: a spring only gets "close enough", so finish exactly.
    _animation.animateWith(
      SpringSimulation(_spring, 0, 1, startSpeed, snapToEnd: true),
    );
  }

  void _slideIn(SwipeDirection from) {
    final sign = from == SwipeDirection.right ? 1.0 : -1.0;
    _offset = Offset(sign * _size.width * 1.2, 0);
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
    widget.dragProgress?.value = (offset.dx / _threshold).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SortColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        // Start off screen on the first frame, then slide in, so the card
        // never flashes in the middle first.
        if (_pendingEntry case final from?) {
          _pendingEntry = null;
          _slideIn(from);
        }
        final progress = (_offset.dx / _threshold).clamp(-1.0, 1.0);
        final tilt =
            _maxTilt * (_offset.dx / math.max(_size.width, 1)).clamp(-1.0, 1.0);

        return GestureDetector(
          // Catch drags anywhere on the card, even on see-through parts.
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Transform.translate(
            offset: _offset,
            child: Transform.rotate(
              angle: tilt,
              // Pivot near the bottom, like a card held at its base.
              alignment: const Alignment(0, 0.8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  Positioned(
                    top: 20,
                    left: 20,
                    child: _Stamp(
                      label: 'KEEP',
                      color: colors.keep,
                      angle: -0.12,
                      strength: progress.clamp(0.0, 1.0),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    right: 20,
                    child: _Stamp(
                      label: 'DELETE',
                      color: colors.delete,
                      angle: 0.12,
                      strength: (-progress).clamp(0.0, 1.0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The KEEP / DELETE label that appears while dragging. [strength] runs
/// from 0 (hidden) to 1 (past the threshold): it fades in and settles from
/// slightly larger to its final size, like being pressed down.
class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.angle,
    required this.strength,
  });

  final String label;
  final Color color;
  final double angle;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: strength,
      child: Transform.scale(
        scale: 1.15 - 0.15 * strength,
        child: Transform.rotate(
          angle: angle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Paper-coloured backing (near-black in dark mode), so the
              // label reads as crisp ink on any photo.
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: 0.92),
              border: Border.all(color: color, width: 2.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
