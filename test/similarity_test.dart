import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/state/similarity.dart';

// How the limit of 12 bits (Similarity.maxBits) was chosen. Measured on the
// Android emulator, with the final method, on real 1200 x 900 JPEGs of four
// scenes, taken from Android's own 128-pixel thumbnails:
//
//   the same scene, plain or brighter or moved 2%  0 bits apart
//   the same scene, heavily blurred                8
//   a second scene, moved and brighter             6
//   two unrelated scenes                           27 to 43
//
// So 12 has headroom above the blurred retake (8), and is well below the
// closest unrelated pair (27).
//
// Two things were learned on the way. Before fingerprints needed a margin to
// call a square "brighter" (`Similarity` margin), the same photos measured
// worse on the phone: a plain brighter copy was 11 bits away, and the
// blurred one 15 to 16, over any sensible limit. Flat areas such as a clear
// sky flip their bits with the slightest change. And sharpness was first the
// plain average change in brightness, which scored a blurred photo higher
// than a sharp one (blur spreads an edge but doesn't change its total
// height); the root of the average squared change scores it lowest.
const _width = 64;
const _height = 48;

// A made-up "photo": blocks of random grey, 4 pixels across, as RGBA bytes.
// The same seed always gives the same photo.
Uint8List noise(int seed, {int shift = 0, bool blurred = false}) {
  final random = Random(seed);
  final blocks = List.generate(
    (_width ~/ 4) * (_height ~/ 4),
    (_) => random.nextInt(256),
  );
  var grey = List.generate(
    _width * _height,
    (i) => blocks[(i ~/ _width ~/ 4) * (_width ~/ 4) + (i % _width) ~/ 4],
  );
  if (blurred) {
    // Each pixel becomes the average of the ones around it.
    for (var pass = 0; pass < 3; pass++) {
      final next = List.of(grey);
      for (var y = 1; y < _height - 1; y++) {
        for (var x = 1; x < _width - 1; x++) {
          var sum = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              sum += grey[(y + dy) * _width + x + dx];
            }
          }
          next[y * _width + x] = sum ~/ 9;
        }
      }
      grey = next;
    }
  }
  final rgba = Uint8List(_width * _height * 4);
  for (var i = 0; i < grey.length; i++) {
    final v = (grey[i] + shift).clamp(0, 255);
    rgba.setRange(i * 4, i * 4 + 4, [v, v, v, 255]);
  }
  return rgba;
}

Fingerprint print(Uint8List rgba) => Similarity.of(rgba, _width, _height)!;

({DateTime date, Fingerprint fingerprint}) shot(
  int seed,
  int minute, {
  int shift = 0,
}) => (
  date: DateTime(2026, 11, 1, 12, minute),
  fingerprint: print(noise(seed, shift: shift)),
);

void main() {
  group('fingerprint', () {
    test('the same photo gives the same fingerprint', () {
      expect(print(noise(1)).hash, print(noise(1)).hash);
    });

    test(
      'a brighter copy is almost the same, and a different photo is not',
      () {
        final original = print(noise(1));
        final brighter = print(noise(1, shift: 20));
        final other = print(noise(2));

        expect(Similarity.distance(original.hash, brighter.hash), lessThan(4));
        expect(
          Similarity.distance(original.hash, other.hash),
          greaterThan(Similarity.maxBits * 2),
        );
      },
    );

    test('specks of noise in a flat area do not change the fingerprint', () {
      // Left half dark, right half bright, so there's one real edge; each
      // copy has its own random speck of up to 1 level on every pixel.
      Uint8List halves(int seed) {
        final random = Random(seed);
        final rgba = Uint8List(_width * _height * 4);
        for (var i = 0; i < _width * _height; i++) {
          final base = (i % _width) < _width ~/ 2 ? 60 : 180;
          final v = base + random.nextInt(3) - 1;
          rgba.setRange(i * 4, i * 4 + 4, [v, v, v, 255]);
        }
        return rgba;
      }

      expect(print(halves(1)).hash, print(halves(2)).hash);
    });

    test('the stamp changes with the date and with the method', () {
      final day = DateTime(2026, 11, 1);
      expect(
        Similarity.stamp(day),
        isNot(Similarity.stamp(day.add(const Duration(seconds: 1)))),
      );
      expect(Similarity.stamp(day) % 100, Similarity.version);
    });

    test('a photo too small to describe has no fingerprint', () {
      expect(Similarity.of(Uint8List(4), 1, 1), isNull);
      expect(Similarity.of(Uint8List(8 * 8 * 4), 8, 8), isNull);
    });

    test('a plain photo is flat, a detailed one is not', () {
      final grey = Uint8List.fromList(
        List.generate(_width * _height * 4, (i) => i % 4 == 3 ? 255 : 128),
      );
      expect(print(grey).isFlat, isTrue);
      expect(print(noise(1)).isFlat, isFalse);
    });

    test('a blurred copy scores lower for sharpness', () {
      expect(
        print(noise(1, blurred: true)).sharpness,
        lessThan(print(noise(1)).sharpness),
      );
    });

    test('the sharpest of a set is found, the later one on a tie', () {
      final sharp = print(noise(1));
      final blurry = print(noise(1, blurred: true));
      expect(Similarity.sharpest([blurry, sharp, blurry]), 1);
      expect(Similarity.sharpest([sharp, sharp]), 1);
    });
  });

  group('colour', () {
    // The same blocks of light and dark, tinted: [red] and [blue] weight the
    // channels, so the layout is the same and the colours differ.
    Fingerprint tinted(int seed, {double red = 1, double blue = 1}) {
      final source = noise(seed);
      final rgba = Uint8List.fromList(source);
      for (var i = 0; i < _width * _height; i++) {
        rgba[i * 4] = (source[i * 4] * red).round().clamp(0, 255);
        rgba[i * 4 + 2] = (source[i * 4 + 2] * blue).round().clamp(0, 255);
      }
      return print(rgba);
    }

    test('is the average of every pixel', () {
      final solid = Uint8List(_width * _height * 4);
      for (var i = 0; i < _width * _height; i++) {
        solid.setRange(i * 4, i * 4 + 4, [200, 20, 10, 255]);
      }
      expect(print(solid).colour, 0xC8140A);
    });

    test('a brighter or darker shot is the same colour', () {
      // Brightness moves all three channels together, not their mix, so the
      // shift stays well inside the limit, even for a big change.
      const limit = Similarity.maxColourShift;
      expect(Similarity.colourShift(0x806040, 0xA08060), lessThan(limit));
      expect(Similarity.colourShift(0x806040, 0x403020), lessThan(limit));
      expect(Similarity.colourShift(0x808080, 0xE0E0E0), lessThan(limit / 2));
    });

    test('red and blue are very different, grey and a slight tint are not', () {
      expect(Similarity.colourShift(0xC03030, 0x3030C0), greaterThan(0.2));
      expect(Similarity.colourShift(0x808080, 0x888078), lessThan(0.03));
      expect(Similarity.colourShift(0x123456, 0x123456), 0);
    });

    test('the same layout in another colour is not a look-alike', () {
      final red = tinted(1, blue: 0.2);
      final blue = tinted(1, red: 0.2);
      // The brightness pattern doesn't see colour, so these look alike to
      // the hash on its own...
      expect(
        Similarity.distance(red.hash, blue.hash),
        lessThanOrEqualTo(Similarity.maxBits),
      );
      // ...which is why the colour has to agree too.
      expect(Similarity.alike(red, blue, Similarity.maxBits), isFalse);
      expect(
        Similarity.group([
          (date: DateTime(2026, 11, 1, 12, 0), fingerprint: red),
          (date: DateTime(2026, 11, 1, 12, 1), fingerprint: blue),
        ]),
        isEmpty,
      );
    });

    test('a brighter copy of a coloured photo is still a look-alike', () {
      final photo = tinted(1, blue: 0.3);
      final lifted = Fingerprint(
        photo.hash,
        photo.sharpness,
        // The same mix of colours, a little brighter.
        0xFFFFFF & (photo.colour + 0x181818),
      );
      expect(Similarity.alike(photo, lifted, Similarity.maxBits), isTrue);
    });
  });

  group('distance', () {
    test('counts the bits that differ, in all 64 places', () {
      expect(Similarity.distance(0, 0), 0);
      expect(Similarity.distance(0, 0xB), 3);
      expect(Similarity.distance(0, -1), 64); // Every bit set.
      expect(Similarity.distance(-1 << 63, 0), 1); // Only the top bit.
      expect(Similarity.distance(5, 5), 0);
    });
  });

  group('which photos are worth comparing', () {
    test('only those with a neighbour in time', () {
      final dates = [
        DateTime(2026, 3, 1, 9), // Alone.
        DateTime(2026, 6, 1, 12, 0),
        DateTime(2026, 6, 1, 12, 4), // Two within ten minutes.
        DateTime(2026, 9, 1, 8), // Alone.
      ];
      expect(Similarity.worthComparing(dates), {1, 2});
    });

    test('whatever order they come in', () {
      final dates = [
        DateTime(2026, 6, 1, 12, 4),
        DateTime(2026, 3, 1),
        DateTime(2026, 6, 1, 12, 0),
      ];
      expect(Similarity.worthComparing(dates), {0, 2});
    });
  });

  group('grouping', () {
    test('look-alikes taken together form a group, oldest first', () {
      final items = [
        shot(1, 3, shift: 15), // Same scene, a little brighter, later.
        shot(1, 0),
        shot(2, 1), // Something else, in between.
        shot(1, 2),
      ];
      expect(Similarity.group(items), [
        [1, 3, 0],
      ]);
    });

    test('look-alikes taken far apart in time are kept apart', () {
      final items = [
        shot(1, 0),
        (date: DateTime(2026, 11, 1, 15), fingerprint: print(noise(1))),
      ];
      expect(Similarity.group(items), isEmpty);
    });

    test('unrelated photos make no group', () {
      expect(Similarity.group([shot(1, 0), shot(2, 1), shot(3, 2)]), isEmpty);
    });

    test('plain photos are never grouped, however alike', () {
      final plain = print(
        Uint8List.fromList(
          List.generate(_width * _height * 4, (i) => i % 4 == 3 ? 255 : 90),
        ),
      );
      final items = [
        (date: DateTime(2026, 11, 1, 12, 0), fingerprint: plain),
        (date: DateTime(2026, 11, 1, 12, 1), fingerprint: plain),
      ];
      expect(Similarity.group(items), isEmpty);
    });

    test('a chain of near matches is one group', () {
      // Each shot differs from the next by a little, but the last differs
      // from the first by more than the limit.
      Fingerprint step(int flips) =>
          Fingerprint(((1 << flips) - 1) ^ 0x5555555555555555, 0.1);
      final items = [
        for (var i = 0; i < 4; i++)
          (date: DateTime(2026, 11, 1, 12, i), fingerprint: step(i * 5)),
      ];
      expect(
        Similarity.distance(
          items.first.fingerprint.hash,
          items.last.fingerprint.hash,
        ),
        greaterThan(Similarity.maxBits),
      );
      expect(Similarity.group(items), [
        [0, 1, 2, 3],
      ]);
    });

    test('a very long chain is split, so no group is over the limit', () {
      Fingerprint step(int flips) =>
          Fingerprint(((1 << flips) - 1) ^ 0x5555555555555555, 0.1);
      // Forty shots, each three bits from the one before.
      final items = [
        for (var i = 0; i < 40; i++)
          (
            date: DateTime(2026, 11, 1, 12, 0, i),
            fingerprint: step(i * 3 % 60),
          ),
      ];
      final groups = Similarity.group(items, gap: const Duration(hours: 1));
      expect(groups, isNotEmpty);
      expect(
        groups.every((g) => g.length <= Similarity.maxGroup && g.length >= 2),
        isTrue,
      );
    });

    test('groups come in the order of their oldest photo', () {
      final items = [shot(5, 30), shot(5, 31), shot(1, 0), shot(1, 1)];
      expect(Similarity.group(items), [
        [2, 3],
        [0, 1],
      ]);
    });
  });
}
