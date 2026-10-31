import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  /// What the card is showing. When it changes, the card resets to the
  /// middle, ready for the next photo.
  final String cardId;

  final ValueChanged<SwipeDirection> onSwiped;
  final Widget child;

  /// Updated from -1 (dragged fully left) to 1 (fully right), so the card
  /// behind can react without rebuilding the whole screen.
  final ValueNotifier<double>? dragProgress;

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
  // Tilt at a full card width of drag, in radians (about 12 degrees).
  static const _maxTilt = 0.2;

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_onAnimate);

  Offset _offset = Offset.zero;
  Offset _animateFrom = Offset.zero;
  Offset _animateTo = Offset.zero;
  Curve _curve = Curves.easeOut;
  SwipeDirection? _leaving; // Set while flying off; ignores more input.
  bool _pastThreshold = false;
  Size _size = Size.zero;

  double get _threshold => math.max(_size.width * _thresholdShare, 1);

  @override
  void didUpdateWidget(SwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) {
      _animation.stop();
      _offset = Offset.zero;
      _leaving = null;
      _pastThreshold = false;
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
    _animateOffset(to: Offset.zero, curve: Curves.easeOutBack);
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

    final speed = details.velocity.pixelsPerSecond.dx;
    final SwipeDirection? direction;
    if (speed.abs() > _flickSpeed) {
      direction = speed > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else if (_offset.dx.abs() > _threshold) {
      direction = _offset.dx > 0 ? SwipeDirection.right : SwipeDirection.left;
    } else {
      direction = null;
    }

    if (direction == null) {
      // easeOutBack overshoots a little, so the card feels springy.
      _animateOffset(to: Offset.zero, curve: Curves.easeOutBack);
    } else {
      _flyOut(direction);
    }
  }

  void _flyOut(SwipeDirection direction) {
    _leaving = direction;
    HapticFeedback.mediumImpact();
    final sign = direction == SwipeDirection.right ? 1.0 : -1.0;
    // Far enough that even the tilted corner ends up off screen.
    final target = Offset(sign * _size.width * 1.5, _offset.dy);
    _animateOffset(to: target, curve: Curves.easeIn).then((_) {
      if (!mounted) return;
      widget.dragProgress?.value = 0;
      widget.onSwiped(direction);
    });
  }

  // The returned future completes only if the animation runs to the end,
  // not if it's stopped because a new photo arrived.
  TickerFuture _animateOffset({required Offset to, required Curve curve}) {
    _animateFrom = _offset;
    _animateTo = to;
    _curve = curve;
    return _animation.forward(from: 0);
  }

  void _onAnimate() {
    final t = _curve.transform(_animation.value);
    _setOffset(Offset.lerp(_animateFrom, _animateTo, t)!);
  }

  void _setOffset(Offset offset) {
    setState(() => _offset = offset);
    widget.dragProgress?.value = (offset.dx / _threshold).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
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
                    top: 24,
                    left: 24,
                    child: Opacity(
                      opacity: progress.clamp(0.0, 1.0),
                      child: const _Stamp(
                        label: 'KEEP',
                        color: _keepColor,
                        angle: -0.25,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: 24,
                    child: Opacity(
                      opacity: (-progress).clamp(0.0, 1.0),
                      child: const _Stamp(
                        label: 'DELETE',
                        color: _deleteColor,
                        angle: 0.25,
                      ),
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

const _keepColor = Color(0xFF2E7D32);
const _deleteColor = Color(0xFFC62828);

/// The KEEP / DELETE label that fades in while dragging.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color, required this.angle});

  final String label;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A pale background keeps the label readable on any photo.
          color: Colors.white.withValues(alpha: 0.85),
          border: Border.all(color: color, width: 4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}
