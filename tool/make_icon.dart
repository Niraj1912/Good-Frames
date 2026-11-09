// Makes Good Frames' launcher icon from the logo artwork.
//
// Run from the project folder:  dart run tool/make_icon.dart
//
// Reads assets/branding/good_frames_logo_source.webp (the logo on a dark
// canvas), finds the rounded tile in it, and writes:
//   assets/branding/good_frames_logo.png  the tile alone, 1024 px
//   android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png
//   windows/runner/resources/app_icon.ico  the Windows app icon
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

Future<void> main() async {
  final source = await img.decodeImageFile('assets/branding/good_frames_logo_source.webp');
  if (source == null) {
    stderr.writeln('Could not read the logo.');
    exit(1);
  }

  // The tile is everything clearly brighter than the dark canvas around it
  // (the canvas measures about 13).
  int minX = source.width, minY = source.height, maxX = 0, maxY = 0;
  for (final p in source) {
    if (p.luminance > 20) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
  }
  final int side = math.max(maxX - minX, maxY - minY) + 1;
  final cx = (minX + maxX) ~/ 2, cy = (minY + maxY) ~/ 2;
  final tile = img.copyCrop(
    source,
    x: cx - side ~/ 2,
    y: cy - side ~/ 2,
    width: side,
    height: side,
  );
  stdout.writeln('Tile: ${side}px square at ($cx, $cy)');

  File('assets/branding/good_frames_logo.png').writeAsBytesSync(
    img.encodePng(
      img.copyResize(tile, width: 1024, height: 1024, interpolation: img.Interpolation.cubic),
    ),
  );

  // The adaptive icon is a full 108 dp canvas (at 10 px per dp) that each
  // launcher masks to its own shape: circle, squircle, hexagon... So the
  // artwork must not be a tile with its own corners and rim, or the mask
  // leaves a ring round it. Instead:
  //   background  the tile's body colour (ic_launcher_background in colors.xml)
  //   foreground  the tile's middle (cards and pills, no rim), feathered into
  //               that same colour and sized to sit inside the 66 dp circle
  //               every mask keeps.
  const canvas = 1080;
  const tilePx = 1024;
  final full = img.copyResize(tile, width: tilePx, height: tilePx, interpolation: img.Interpolation.cubic);

  // The cards and arrows reach about 415 px from the middle of the artwork
  // (which sits at 510, 467 in the 1024 px tile, a little above the tile's
  // centre); keep that inside the 330 px radius of the safe circle.
  const scale = 330 / 415;
  const artX = 510.0, artY = 467.0;
  final size = (tilePx * scale).round();
  final scaled = img.copyResize(full, width: size, height: size, interpolation: img.Interpolation.cubic);
  final offsetX = (canvas / 2 - artX * scale).round();
  final offsetY = (canvas / 2 - artY * scale).round();

  // A rounded rectangle round the cards and arrows (in the 1024 px tile) that fades from opaque to clear
  // at its edge, keeping the glow-free middle and dropping the rim.
  const left = 100.0, right = 925.0, top = 165.0, bottom = 785.0;
  const radius = 100.0, feather = 28.0;
  double alphaAt(double x, double y) {
    final cx = (left + right) / 2, cy = (top + bottom) / 2;
    final hx = (right - left) / 2 - radius, hy = (bottom - top) / 2 - radius;
    final qx = (x - cx).abs() - hx, qy = (y - cy).abs() - hy;
    final d = math.sqrt(math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2)) +
        math.min(math.max(qx, qy), 0) -
        radius;
    final fade = (-d / feather).clamp(0.0, 1.0);
    // The tile's own corner glow reaches into the top corners of that
    // rectangle, well clear of any card: fade it out too.
    double corner(double edge, double along) =>
        ((edge) / 20).clamp(0.0, 1.0) * ((along) / 20).clamp(0.0, 1.0);
    final cut = math.max(corner(285 - x, 305 - y), corner(x - 780, 280 - y));
    return fade * (1 - cut);
  }

  // The tile's body colour, which the icon background uses too, so the
  // layer is solid edge to edge and nothing shows a seam.
  const body = (r: 6, g: 28, b: 43);
  final layer = img.Image(width: canvas, height: canvas, numChannels: 4);
  img.fill(layer, color: img.ColorRgba8(body.r, body.g, body.b, 255));
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final a = alphaAt(x / scale, y / scale);
      if (a <= 0) continue;
      final p = scaled.getPixel(x, y);
      layer.setPixelRgba(
        x + offsetX,
        y + offsetY,
        (body.r + (p.r - body.r) * a).round(),
        (body.g + (p.g - body.g) * a).round(),
        (body.b + (p.b - body.b) * a).round(),
        255,
      );
    }
  }

  final out = Directory('android/app/src/main/res/drawable-nodpi')..createSync();
  File('${out.path}/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(layer));

  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
    img.encodeIco(
      img.copyResize(tile, width: 256, height: 256, interpolation: img.Interpolation.cubic),
    ),
  );
}
