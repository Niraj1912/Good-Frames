import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A made-up photo as PNG bytes: blocks of random grey, 4 pixels across,
/// 64 x 48. The same [seed] always gives the same picture, a [shift] makes
/// it brighter or darker (like a second shot in slightly different light),
/// and [blurred] softens it (like a shot that moved).
Uint8List photoPng(int seed, {int shift = 0, bool blurred = false}) {
  const width = 64;
  const height = 48;
  final random = Random(seed);
  final blocks = List.generate(
    (width ~/ 4) * (height ~/ 4),
    (_) => random.nextInt(256),
  );
  var grey = List.generate(
    width * height,
    (i) => blocks[(i ~/ width ~/ 4) * (width ~/ 4) + (i % width) ~/ 4],
  );
  if (blurred) {
    for (var pass = 0; pass < 3; pass++) {
      final next = List.of(grey);
      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          var sum = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              sum += grey[(y + dy) * width + x + dx];
            }
          }
          next[y * width + x] = sum ~/ 9;
        }
      }
      grey = next;
    }
  }
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (grey[y * width + x] + shift).clamp(0, 255);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
