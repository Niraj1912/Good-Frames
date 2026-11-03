import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/photo_frame.dart';

/// A photo as a card of its own shape: as large as fits, never cropped,
/// with rounded corners and nothing around it. A portrait photo makes a
/// tall card and a landscape one a wide card, like a print.
///
/// It needs loose constraints (inside a Center, say) to take the photo's
/// shape. Until the photo is decoded its shape isn't known, so it keeps
/// the previous photo's shape, or a 3:4 one for the first.
class PhotoCard extends StatefulWidget {
  const PhotoCard({super.key, required this.image, this.heroTag});

  final ImageProvider image;

  /// Set on the top card only, so the photo can grow into the zoom viewer.
  final Object? heroTag;

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> {
  static const _radius = BorderRadius.all(Radius.circular(16));

  // Width over height of the photo being shown.
  double _aspectRatio = 3 / 4;
  bool _broken = false;
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  // Asks for the photo, the same way its Image does, so both share one
  // decoded copy from Flutter's image cache.
  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final ratio = info.image.width / info.image.height;
    info.dispose(); // Only its size was needed.
    if (!mounted) return;
    setState(() {
      _aspectRatio = ratio;
      _broken = false;
    });
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (mounted) setState(() => _broken = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = PhotoFrame(image: widget.image);
    return AspectRatio(
      aspectRatio: _broken ? 3 / 4 : _aspectRatio,
      child: Container(
        // A photo that can't be shown gets a dark card, so its message has
        // somewhere to sit; a real photo needs nothing behind it.
        decoration: BoxDecoration(
          color: _broken ? SortColors.of(context).frame : null,
          borderRadius: _radius,
        ),
        // A faint line just inside the edge, so a photo close to the
        // page's colour (a white wall, a night sky) still has an edge.
        foregroundDecoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
          borderRadius: _radius,
        ),
        clipBehavior: Clip.antiAlias,
        // The dark theme inside, so a broken photo's message is light on
        // the dark card. The Material passes the theme's text colour on to
        // plain Text too.
        child: Theme(
          data: AppTheme.dark,
          child: Material(
            type: MaterialType.transparency,
            child: switch (widget.heroTag) {
              final tag? => Hero(tag: tag, child: photo),
              null => photo,
            },
          ),
        ),
      ),
    );
  }
}
