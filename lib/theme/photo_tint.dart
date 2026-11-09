import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:good_frames/data/image_decoding.dart';

/// Finds a photo's main colour, so the area around it can wear a soft tint
/// of it: each album's name sits on a panel tinted from its cover. The
/// colour comes from the pictures, so it never competes with them.
///
/// It uses Material's colour science, the same that picks Android's colours
/// from the wallpaper. Colours are handled as HCT: hue, chroma (how
/// colourful) and tone (how light, 0 black to 100 white). Tone sets
/// contrast, so a tint at a fixed tone keeps text readable whatever the
/// photo's colour.
abstract final class PhotoTint {
  /// The width of the copy the colour is found from. A tiny copy is
  /// plenty, and quick to decode.
  static const sampleWidth = 32;

  // Recent answers by photo id, oldest first. Futures, so a photo asked
  // for again while its colour is still being found shares the one job.
  static final _cache = <String, Future<Color?>>{};
  static const _cacheSize = 500;

  /// The main colour of photo [id], found from [sample], a copy of it
  /// [sampleWidth] wide. Null for a photo with no main colour (a grey
  /// one, say) or one that can't be decoded: those get no tint.
  static Future<Color?> of(String id, ImageProvider sample) {
    // Removed and added again, so it counts as recently used.
    final found = _cache.remove(id) ?? _find(sample);
    _cache[id] = found;
    if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
    return found;
  }

  /// A panel tinted with [seed], such as an album's name under its cover.
  /// Light enough for the theme's dark text, or dark enough for its light
  /// text in dark mode.
  static Color panel(Color seed, Brightness brightness) =>
      brightness == Brightness.light
      ? _atTone(seed, tone: 90, maxChroma: 24)
      : _atTone(seed, tone: 24, maxChroma: 18);

  // The seed's hue at [tone], no more colourful than [maxChroma]: a vivid
  // red photo gives a soft rose, not a red screen.
  static Color _atTone(
    Color seed, {
    required double tone,
    required double maxChroma,
  }) {
    final hct = Hct.fromInt(seed.toARGB32());
    return Color(Hct.from(hct.hue, min(hct.chroma, maxChroma), tone).toInt());
  }

  static Future<Color?> _find(ImageProvider sample) async {
    try {
      final pixels = await _pixels(sample);
      // Off the main thread, so finding it never stutters scrolling.
      final argb = await compute(mainColour, pixels);
      return argb == null ? null : Color(argb);
    } catch (_) {
      return null; // A photo that can't be decoded just gets no tint.
    }
  }

  /// The main colour among [pixels] (each 0xAARRGGBB), or null if none is
  /// colourful enough. Groups the pixels into at most 32 colours, then
  /// picks the one with the best mix of how much of the photo it covers
  /// and how colourful it is.
  @visibleForTesting
  static Future<int?> mainColour(Uint32List pixels) async {
    if (pixels.isEmpty) return null;
    final groups = await QuantizerCelebi().quantize(pixels, 32);
    // Score leaves out colours too grey or too rare to be the main one,
    // and gives the fallback if none is left. 0 is see-through, so it
    // can't be a real answer.
    final best = Score.score(
      groups.colorToCount,
      desired: 1,
      fallbackColorARGB: 0,
    ).first;
    return best == 0 ? null : best;
  }

  // The sample's pixels as 0xAARRGGBB, skipping see-through ones.
  static Future<Uint32List> _pixels(ImageProvider sample) async {
    final image = await decodeImage(sample);
    try {
      final data = await image.toByteData(); // RGBA, 4 bytes a pixel
      if (data == null) return Uint32List(0);
      final bytes = data.buffer.asUint8List();
      final pixels = <int>[];
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (bytes[i + 3] < 255) continue;
        pixels.add(
          0xFF000000 | bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2],
        );
      }
      return Uint32List.fromList(pixels);
    } finally {
      image.dispose();
    }
  }
}

/// Builds with the main colour of photo [id] once it's known, or null
/// until then and for photos without one (see [PhotoTint.of]).
///
/// When [id] changes, the old colour stays until the new one is found, so
/// the tint changes once instead of flashing back to plain in between.
class PhotoTintBuilder extends StatefulWidget {
  const PhotoTintBuilder({
    super.key,
    required this.id,
    required this.sample,
    required this.builder,
  });

  /// The photo, or null for none (no tint).
  final String? id;

  /// A copy of the photo [PhotoTint.sampleWidth] wide. Only read when
  /// [id] changes.
  final ImageProvider? Function() sample;

  final Widget Function(BuildContext context, Color? seed) builder;

  @override
  State<PhotoTintBuilder> createState() => _PhotoTintBuilderState();
}

class _PhotoTintBuilderState extends State<PhotoTintBuilder> {
  Color? _seed;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(PhotoTintBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.id != oldWidget.id) _find();
  }

  void _find() {
    final id = widget.id;
    final sample = id == null ? null : widget.sample();
    if (id == null || sample == null) {
      _seed = null; // Called before a build, so no setState needed.
      return;
    }
    PhotoTint.of(id, sample).then((seed) {
      // Still the same photo, and the colour is new.
      if (mounted && widget.id == id && seed != _seed) {
        setState(() => _seed = seed);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _seed);
}
