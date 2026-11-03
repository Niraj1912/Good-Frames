import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/photo_tint.dart';

import 'support/contrast.dart';

Uint32List filled(int argb, int count) =>
    Uint32List.fromList(List.filled(count, argb));

void main() {
  test('finds the main colour of a mostly red photo', () async {
    // Three quarters red, a quarter dark grey.
    final pixels = Uint32List.fromList([
      ...filled(0xFFCC2222, 768),
      ...filled(0xFF333333, 256),
    ]);

    final found = await PhotoTint.mainColour(pixels);

    final hue = Hct.fromInt(found!).hue;
    final red = Hct.fromInt(0xFFCC2222).hue;
    expect((hue - red).abs(), lessThan(10));
  });

  test('a grey photo has no main colour, so it gets no tint', () async {
    expect(await PhotoTint.mainColour(filled(0xFF808080, 1024)), isNull);
    expect(await PhotoTint.mainColour(Uint32List(0)), isNull);
  });

  test('text stays readable on the tint of any colour', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final colors = theme.colorScheme;
      // Vivid colours all the way round the colour wheel.
      for (var hue = 0.0; hue < 360; hue += 15) {
        final seed = Color(Hct.from(hue, 80, 50).toInt());
        final panel = PhotoTint.panel(seed, theme.brightness);
        for (final text in [colors.onSurface, colors.onSurfaceVariant]) {
          expect(
            contrast(text, panel),
            greaterThan(4.5),
            reason: '${theme.brightness.name} mode, hue $hue',
          );
        }
      }
    }
  });

  test('a vivid photo gives a soft tint, not a loud one', () {
    final vivid = Color(Hct.from(25, 100, 50).toInt());
    final tint = Hct.fromInt(
      PhotoTint.panel(vivid, Brightness.light).toARGB32(),
    );
    expect(tint.chroma, lessThanOrEqualTo(25));
    expect(tint.tone, closeTo(88, 1));
  });

  test('the keep and delete counts are readable on their soft washes', () {
    for (final (theme, sort) in [
      (AppTheme.light, SortColors.light),
      (AppTheme.dark, SortColors.dark),
    ]) {
      for (final colour in [sort.keep, sort.delete]) {
        // As the counts above the photo draw them.
        final wash = Color.alphaBlend(
          colour.withValues(alpha: 0.10),
          theme.colorScheme.surface,
        );
        expect(
          contrast(colour, wash),
          greaterThan(4.5),
          reason: theme.brightness.name,
        );
      }
    }
  });

  testWidgets('finds the colour of a real image, and remembers it', (
    tester,
  ) async {
    final png = img.encodePng(
      img.fill(
        img.Image(width: 32, height: 32),
        color: img.ColorRgb8(34, 102, 204),
      ),
    );
    final sample = MemoryImage(png);

    // Decoding is real work, so it runs outside the test's fake clock.
    final (first, again) = (await tester.runAsync(() async {
      final first = PhotoTint.of('blue', sample);
      final again = PhotoTint.of('blue', sample);
      return (first, again);
    }))!;
    final colour = await tester.runAsync(() => first);

    expect(identical(first, again), isTrue);
    final hue = Hct.fromInt(colour!.toARGB32()).hue;
    expect((hue - Hct.fromInt(0xFF2266CC).hue).abs(), lessThan(10));
  });
}
