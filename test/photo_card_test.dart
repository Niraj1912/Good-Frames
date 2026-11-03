import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_swipe/widgets/photo_card.dart';

void main() {
  // A card in a 300 x 600 area, centred so it can take its own shape.
  Future<void> showCard(WidgetTester tester, ImageProvider image) async {
    // Decoding is real work, so it runs outside the test's fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 600,
              child: Center(child: PhotoCard(image: image)),
            ),
          ),
        ),
      );
      final element = tester.element(find.byType(PhotoCard));
      await precacheImage(image, element, onError: (_, _) {});
    });
    await tester.pumpAndSettle();
  }

  testWidgets('takes the shape of a landscape photo, without cropping', (
    tester,
  ) async {
    final wide = MemoryImage(img.encodePng(img.Image(width: 400, height: 200)));

    await showCard(tester, wide);

    // As wide as the area, and half as tall: no bars, nothing cut off.
    expect(tester.getSize(find.byType(PhotoCard)), const Size(300, 150));
  });

  testWidgets('a photo that cannot be shown gets a card with a message', (
    tester,
  ) async {
    final broken = MemoryImage(Uint8List.fromList([1, 2, 3]));

    await showCard(tester, broken);

    // Light text, readable on the dark card even in light mode.
    final message = tester.renderObject<RenderParagraph>(
      find.text("Can't display this photo"),
    );
    expect(message.text.style!.color!.computeLuminance(), greaterThan(0.5));
    expect(tester.getSize(find.byType(PhotoCard)), const Size(300, 400));
  });
}
