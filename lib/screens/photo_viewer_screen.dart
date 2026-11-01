import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/decision_buttons.dart';
import 'package:photo_swipe/widgets/formatting.dart';

/// One photo, full screen and zoomable, for checking whether it's sharp
/// before deciding. Pinch or double-tap to zoom (double-tap jumps to 100%:
/// one photo pixel per screen pixel), drag to look around.
///
/// Pops with the [Decision] if the user makes one here, or null if they
/// just close it.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.repository,
    required this.photo,
    required this.preview,
    required this.heroTag,
  });

  final PhotoRepository repository;
  final Photo photo;

  /// The screen-sized image already on the card, shown straight away while
  /// the detailed one loads.
  final ImageProvider preview;

  /// Matches the card's, so the photo grows from the card into this screen.
  final Object heroTag;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen>
    with SingleTickerProviderStateMixin {
  late final ImageProvider _detail = widget.repository.detailImageFor(
    widget.photo,
  );
  final _transform = TransformationController();
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(_onZoomTick);
  Matrix4Tween? _zoomTween;

  // The detailed image's real size in pixels, once it has loaded.
  Size? _imagePixels;
  ImageStream? _stream;
  late final _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _imagePixels = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
    });
  }, onError: (_, _) {});

  Size _viewport = Size.zero;
  Offset _doubleTapAt = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) {
      _stream = _detail.resolve(createLocalImageConfiguration(context));
      _stream!.addListener(_listener);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _zoom.dispose();
    _transform.dispose();
    // The detailed image is big: free it now instead of letting it sit in
    // the image cache until something pushes it out.
    _detail.evict();
    super.dispose();
  }

  /// How far to zoom so one image pixel covers one physical screen pixel.
  /// Small photos still zoom in noticeably.
  double get _actualPixelsZoom {
    final pixels = _imagePixels;
    if (pixels == null || _viewport.isEmpty) return 2.5;
    final shown = applyBoxFit(BoxFit.contain, pixels, _viewport).destination;
    final zoom =
        pixels.width / MediaQuery.devicePixelRatioOf(context) / shown.width;
    return math.max(zoom, 2.5);
  }

  double get _maxZoom => math.max(4, _actualPixelsZoom * 2);

  void _onDoubleTap() {
    final zoomedIn = _transform.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomedIn) {
      target = Matrix4.identity();
    } else {
      final zoom = _actualPixelsZoom;
      final point = _doubleTapAt;
      // Zoom around the tapped point, so it stays under the finger.
      target = Matrix4.diagonal3Values(zoom, zoom, 1)
        ..setTranslationRaw(-point.dx * (zoom - 1), -point.dy * (zoom - 1), 0);
    }
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target);
    _zoom.forward(from: 0);
  }

  void _onZoomTick() {
    final t = Curves.easeOutCubic.transform(_zoom.value);
    _transform.value = _zoomTween!.lerp(t);
  }

  void _close([Decision? decision]) => Navigator.of(context).pop(decision);

  @override
  Widget build(BuildContext context) {
    // Photos are judged best against black, whatever the app's theme.
    return Theme(
      data: AppTheme.dark,
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    final pixels = _imagePixels;
    final details = [
      formatDate(widget.photo.date),
      if (widget.photo.sizeBytes case final bytes?) formatSize(bytes),
      if (pixels != null)
        '${formatCount(pixels.width.round())} × '
            '${formatCount(pixels.height.round())}',
    ].join('  ·  ');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
        title: Text(
          widget.photo.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _close(Decision.delete),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _close(Decision.keep),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              return GestureDetector(
                onDoubleTapDown: (details) =>
                    _doubleTapAt = details.localPosition,
                onDoubleTap: _onDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transform,
                  maxScale: _maxZoom,
                  child: SizedBox.expand(
                    child: Hero(
                      tag: widget.heroTag,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: widget.preview,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                          // Fades in over the preview once decoded. If it
                          // fails, the preview simply stays.
                          Image(
                            key: const ValueKey('detail'),
                            image: _detail,
                            fit: BoxFit.contain,
                            frameBuilder: (context, child, frame, _) =>
                                AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 200),
                                  child: child,
                                ),
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                details,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: AppTheme.tabularFigures,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Double-tap for 100%. Pinch to zoom, drag to look around.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              DecisionButtons(
                onDelete: () => _close(Decision.delete),
                onKeep: () => _close(Decision.keep),
                onUndo: null,
                showUndo: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
