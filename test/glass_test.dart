import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/theme/photo_tint.dart';

import 'support/contrast.dart';

void main() {
  final modes = [
    (AppTheme.light, GlassColors.light),
    (AppTheme.dark, GlassColors.dark),
  ];

  // The background at its most colourful: the middle of each field of
  // colour, halfway between two of them, and the plain paper between.
  List<Color> backgrounds(GlassColors glass) {
    final fields = [
      for (final blob in glass.blobs) Color.alphaBlend(blob, glass.base),
    ];
    return [
      glass.base,
      ...fields,
      for (var i = 0; i < fields.length; i++)
        for (var j = i + 1; j < fields.length; j++)
          Color.lerp(fields[i], fields[j], 0.5)!,
    ];
  }

  void expectReadable(
    ThemeData theme,
    Color behind,
    String where, {
    bool accent = false,
  }) {
    final colors = theme.colorScheme;
    for (final text in [
      colors.onSurface,
      colors.onSurfaceVariant,
      if (accent) colors.primary,
    ]) {
      expect(
        contrast(text, behind),
        greaterThan(4.5),
        reason: '${theme.brightness.name} mode, $where',
      );
    }
  }

  test('text, including the blue headings, reads on the background', () {
    for (final (theme, glass) in modes) {
      for (final behind in backgrounds(glass)) {
        expectReadable(theme, behind, 'background $behind', accent: true);
      }
    }
  });

  test('text reads on glass, top and bottom, wherever it is', () {
    for (final (theme, glass) in modes) {
      for (final behind in backgrounds(glass)) {
        for (final pane in [glass.sheen, glass.fill]) {
          expectReadable(
            theme,
            Color.alphaBlend(pane, behind),
            'glass $pane over $behind',
          );
        }
      }
    }
  });

  test('text reads on the sheet over any photo, from white to black', () {
    for (final (theme, glass) in modes) {
      for (final photo in [Colors.white, Colors.black, Colors.red]) {
        expectReadable(
          theme,
          Color.alphaBlend(glass.overPhotos, photo),
          'sheet over $photo',
          accent: true,
        );
      }
    }
  });

  test('album names read on glass tinted from any cover', () {
    for (final (theme, glass) in modes) {
      for (var hue = 0.0; hue < 360; hue += 30) {
        final cover = Color(Hct.from(hue, 80, 50).toInt());
        final tint = PhotoTint.panel(
          cover,
          theme.brightness,
        ).withValues(alpha: AppTheme.tintedGlass);
        for (final behind in backgrounds(glass)) {
          for (final pane in [Color.alphaBlend(glass.shine, tint), tint]) {
            expectReadable(
              theme,
              Color.alphaBlend(pane, behind),
              'hue $hue over $behind',
            );
          }
        }
      }
    }
  });

  testWidgets('only glass that asks for it blurs, as blurring is costly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const GlassBackground(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Glass(child: Text('Plain')),
              Glass(blur: true, child: Text('Over a photo')),
            ],
          ),
        ),
      ),
    );

    Finder blurAbove(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byType(BackdropFilter),
    );
    expect(blurAbove('Plain'), findsNothing);
    expect(blurAbove('Over a photo'), findsOneWidget);
  });
}
