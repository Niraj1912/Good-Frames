import 'dart:math';
import 'dart:typed_data';

import 'package:good_frames/models/fingerprint.dart';

export 'package:good_frames/models/fingerprint.dart';

/// Finding photos that look alike, by comparing fingerprints. All of it works
/// on plain numbers, so none of it needs the phone, the screen or the
/// database.
///
/// How a fingerprint works (a "difference hash"): shrink the photo to a
/// 9 x 8 grid of grey squares, then for each square ask one question: "is it
/// brighter than the square to its right?" The 64 answers (8 rows of 8) are
/// the 64 bits. Shots of the same scene, even slightly brighter, a little
/// shifted or recompressed, keep nearly the same pattern of brighter and
/// darker, so their fingerprints differ in only a few bits. The number of
/// bits that differ is the "Hamming distance".
abstract final class Similarity {
  /// Photos whose fingerprints differ in at most this many of the 64 bits
  /// count as look-alikes. Zero is a copy or a brighter or slightly moved
  /// shot; a heavily blurred retake measured 8; unrelated photos measured
  /// 27 or more (usually about 30). So 12 leaves headroom on both sides.
  /// Measured on real photos, on a phone: see test/similarity_test.dart.
  static const maxBits = 12;

  /// Look-alikes are only looked for among photos taken this close in time:
  /// bursts and retakes happen within moments, and it keeps two similar but
  /// unrelated photos (a white wall in March, another in June) apart.
  static const maxGap = Duration(minutes: 10);

  /// ...and only among this many photos after each one in time.
  static const window = 30;

  /// Which way of making fingerprints this is. Changing how they're made
  /// means every saved one is out of date, so it's part of [stamp]: raise
  /// it, and photos are fingerprinted again the next time.
  static const version = 3;

  /// What's saved next to a fingerprint to tell if it's still true: the
  /// photo's date, and the [version] of the method. A photo that has been
  /// edited keeps its place in the album but not (usually) its date.
  static int stamp(DateTime date) =>
      date.millisecondsSinceEpoch * 100 + version;

  /// Photos also have to be alike in colour: how much their share of red,
  /// green or blue may differ (from 0 to 1, see [colourShift]). Shots of one
  /// scene keep their colours, even brighter or darker; a red screenshot and
  /// a blue one laid out alike do not.
  static const maxColourShift = 0.06;

  /// A group is never bigger than this. Chains of look-alikes (A looks like
  /// B, B like C, and so on) could otherwise join dozens of photos that
  /// aren't really alike.
  static const maxGroup = 20;

  /// The fingerprint of a photo, from its pixels as RGBA bytes (4 a pixel,
  /// [width] x [height]), or null if it's too small to describe.
  static Fingerprint? of(Uint8List rgba, int width, int height) {
    if (width < 9 || height < 8 || rgba.length < width * height * 4) {
      return null;
    }
    final grey = Uint8List(width * height);
    for (var i = 0; i < grey.length; i++) {
      final p = i * 4;
      // How bright the eye finds it: green counts most, blue least.
      grey[i] = (rgba[p] * 299 + rgba[p + 1] * 587 + rgba[p + 2] * 114) ~/ 1000;
    }
    return Fingerprint(
      _differenceHash(grey, width, height),
      _sharpness(grey, width, height),
      _averageColour(rgba, width * height),
    );
  }

  // The average of every pixel, as 0xRRGGBB.
  static int _averageColour(Uint8List rgba, int pixels) {
    var red = 0;
    var green = 0;
    var blue = 0;
    for (var i = 0; i < pixels; i++) {
      red += rgba[i * 4];
      green += rgba[i * 4 + 1];
      blue += rgba[i * 4 + 2];
    }
    return (red ~/ pixels) << 16 | (green ~/ pixels) << 8 | (blue ~/ pixels);
  }

  /// How different two average colours are, from 0 (the same) to 1: the
  /// biggest difference in the share of red or of green in the colour. It's
  /// about the mix of colours and not their brightness, so a shot that came
  /// out brighter or darker is no different. (A little is added to the total
  /// so that near-black colours, which are mostly noise, don't jump about.)
  static double colourShift(int a, int b) {
    double share(int colour, int shift) {
      final red = colour >> 16 & 0xFF;
      final green = colour >> 8 & 0xFF;
      final blue = colour & 0xFF;
      return ((colour >> shift) & 0xFF) / (red + green + blue + 30);
    }

    return max(
      (share(a, 16) - share(b, 16)).abs(),
      (share(a, 8) - share(b, 8)).abs(),
    );
  }

  /// Whether two fingerprints are of look-alikes: close in brightness
  /// pattern, and in colour.
  static bool alike(Fingerprint a, Fingerprint b, int bits) =>
      distance(a.hash, b.hash) <= bits &&
      colourShift(a.colour, b.colour) <= maxColourShift;

  // How much brighter a square must be than its neighbour to count, on the
  // 0 to 255 scale.
  static const _margin = 2.0;

  // The 64 answers. Each of the 9 x 8 squares is the average of the pixels
  // it covers.
  static int _differenceHash(Uint8List grey, int width, int height) {
    final cells = List.filled(9 * 8, 0.0);
    for (var cy = 0; cy < 8; cy++) {
      final y0 = cy * height ~/ 8;
      final y1 = ((cy + 1) * height ~/ 8).clamp(y0 + 1, height);
      for (var cx = 0; cx < 9; cx++) {
        final x0 = cx * width ~/ 9;
        final x1 = ((cx + 1) * width ~/ 9).clamp(x0 + 1, width);
        var sum = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            sum += grey[y * width + x];
          }
        }
        cells[cy * 9 + cx] = sum / ((y1 - y0) * (x1 - x0));
      }
    }
    var hash = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        // Brighter by more than a margin, not merely brighter. In a flat
        // area (a clear sky, a plain wall) the two squares differ by a
        // hair, and which is "brighter" flips with the slightest change in
        // light or compression. With a margin, such places always answer
        // "no", and only real differences count.
        if (cells[y * 9 + x] - cells[y * 9 + x + 1] > _margin) {
          hash |= 1 << (y * 8 + x);
        }
      }
    }
    return hash;
  }

  // How abruptly brightness changes from each pixel to its neighbours: the
  // root of the average of the squared changes, as a share of the full
  // range. Squaring is what makes it tell sharp from blurred: a crisp edge
  // is one big step, a blurred one the same step spread over many small
  // ones, and a big step counts for far more once squared. (The plain
  // average change comes out the same for both.)
  static double _sharpness(Uint8List grey, int width, int height) {
    var total = 0;
    for (var y = 0; y < height - 1; y++) {
      for (var x = 0; x < width - 1; x++) {
        final here = grey[y * width + x];
        final right = here - grey[y * width + x + 1];
        final below = here - grey[(y + 1) * width + x];
        total += right * right + below * below;
      }
    }
    final pairs = (width - 1) * (height - 1) * 2;
    return sqrt(total / pairs) / 255;
  }

  /// How many of the 64 bits differ between two fingerprints.
  static int distance(int a, int b) {
    final differing = a ^ b;
    // Counted in two halves of 32 bits: simple, and the same on every
    // platform.
    return _ones(differing & 0xFFFFFFFF) +
        _ones((differing >> 32) & 0xFFFFFFFF);
  }

  static int _ones(int bits) {
    var count = 0;
    while (bits != 0) {
      bits &= bits - 1; // Clears the lowest set bit.
      count++;
    }
    return count;
  }

  /// Which photos are worth fingerprinting: only those with another photo
  /// taken within [gap] of them, since a photo with no neighbour in time
  /// can't be in a group. Returns the positions in [dates].
  static Set<int> worthComparing(
    List<DateTime> dates, {
    Duration gap = maxGap,
  }) {
    final order = _byDate(dates.length, (i) => dates[i]);
    final found = <int>{};
    for (var k = 0; k + 1 < order.length; k++) {
      final a = order[k];
      final b = order[k + 1];
      if (dates[b].difference(dates[a]) <= gap) {
        found.addAll([a, b]);
      }
    }
    return found;
  }

  /// Groups of look-alikes among [items], as positions in [items]. Each
  /// group has two or more photos, oldest first, and the groups are in the
  /// order of their oldest photo.
  ///
  /// Each photo is only compared with the next [window] photos taken within
  /// [gap] of it. Photos that are close enough join the same group, so a
  /// chain of near matches (a burst where the subject slowly moves) ends up
  /// as one group. A chain longer than [maxGroup] is split up again, by
  /// comparing each photo with the first of its group instead.
  static List<List<int>> group(
    List<({DateTime date, Fingerprint fingerprint})> items, {
    int bits = maxBits,
    Duration gap = maxGap,
    int window = Similarity.window,
    int maxGroup = Similarity.maxGroup,
  }) {
    // Photos without detail are left out, as any two would look alike.
    final order = _byDate(items.length, (i) => items[i].date)
      ..removeWhere((i) => items[i].fingerprint.isFlat);

    final parent = List.generate(order.length, (k) => k);
    int root(int k) {
      while (parent[k] != k) {
        parent[k] = parent[parent[k]]; // Shortens the path as it goes.
        k = parent[k];
      }
      return k;
    }

    for (var a = 0; a < order.length; a++) {
      for (var b = a + 1; b < order.length && b <= a + window; b++) {
        final first = items[order[a]];
        final second = items[order[b]];
        if (second.date.difference(first.date) > gap) break;
        if (alike(first.fingerprint, second.fingerprint, bits)) {
          parent[root(a)] = root(b);
        }
      }
    }

    final joined = <int, List<int>>{};
    for (var k = 0; k < order.length; k++) {
      joined.putIfAbsent(root(k), () => []).add(order[k]);
    }

    final groups = <List<int>>[];
    for (final members in joined.values) {
      if (members.length <= maxGroup) {
        groups.add(members);
      } else {
        groups.addAll(_splitByFirst(members, items, bits, maxGroup));
      }
    }
    groups.removeWhere((members) => members.length < 2);
    groups.sort((a, b) => items[a.first].date.compareTo(items[b.first].date));
    return groups;
  }

  // Splits an over-long chain: each photo, in time order, joins the first
  // group whose first photo it still looks like (and which has room).
  static List<List<int>> _splitByFirst(
    List<int> members,
    List<({DateTime date, Fingerprint fingerprint})> items,
    int bits,
    int maxGroup,
  ) {
    final groups = <List<int>>[];
    for (final m in members) {
      final home = groups.where(
        (g) =>
            g.length < maxGroup &&
            alike(items[g.first].fingerprint, items[m].fingerprint, bits),
      );
      if (home.isEmpty) {
        groups.add([m]);
      } else {
        home.first.add(m);
      }
    }
    return groups;
  }

  /// The position of the sharpest photo in [fingerprints]. A tie goes to the
  /// later one: a retake is usually taken because the first wasn't right.
  static int sharpest(List<Fingerprint> fingerprints) {
    var best = 0;
    for (var i = 1; i < fingerprints.length; i++) {
      if (fingerprints[i].sharpness >= fingerprints[best].sharpness) best = i;
    }
    return best;
  }

  // Positions 0 .. count - 1 in order of [dateOf], oldest first.
  static List<int> _byDate(int count, DateTime Function(int) dateOf) {
    return List.generate(count, (i) => i)..sort((a, b) {
      final byDate = dateOf(a).compareTo(dateOf(b));
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }
}
