import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/state/settings.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_images.dart';
import 'support/test_store.dart';

// A count above the photo, such as "Keep 2".
Finder countChip(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

// One photo's tile in a group, by file name.
Finder tile(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('$name,') ?? false),
);

void main() {
  // Five shots, 30 seconds apart: IMG_1, IMG_2 and IMG_3 are the same scene
  // (IMG_3 blurred), IMG_4 and IMG_5 are other scenes.
  FakePhotoRepository fiveShots() {
    return FakePhotoRepository(
        photoCounts: {'Camera': 5},
        spacing: const Duration(seconds: 30),
      )
      ..images['Camera/1'] = photoPng(1)
      ..images['Camera/2'] = photoPng(1, shift: 15)
      ..images['Camera/3'] = photoPng(1, blurred: true)
      ..images['Camera/4'] = photoPng(2)
      ..images['Camera/5'] = photoPng(3);
  }

  Future<void> openSimilar(
    WidgetTester tester,
    FakePhotoRepository repository,
  ) async {
    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      PhotoSwipeApp(
        repository: repository,
        store: store,
        settings: await Settings.load(store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Find similar photos'));
    await tester.pump(const Duration(milliseconds: 500));
    // Looking at the photos is real work, so it runs outside the test's
    // clock: give it time, then wait until the progress bar is gone.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows a group, and keeping the suggestion marks the rest', (
    tester,
  ) async {
    await openSimilar(tester, fiveShots());

    expect(find.text('Group 1 of 1'), findsOneWidget);
    expect(find.text('3 shots, taken within 1 minute'), findsOneWidget);
    // Exactly one photo is suggested, and it isn't the blurred one.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label?.contains('suggested') ?? false),
      ),
      findsOneWidget,
    );
    expect(tile('IMG_3.jpg').evaluate(), isNotEmpty);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'IMG_3.jpg, marked to delete',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep 1, mark 2 to delete'));
    await tester.pumpAndSettle();
    expect(find.text('All groups done'), findsOneWidget);

    await tester.tap(find.text('Back to sorting'));
    await tester.pumpAndSettle();
    expect(countChip('Keep 1'), findsOneWidget);
    expect(countChip('Delete 2'), findsOneWidget);

    // One tap on Undo takes the whole group back.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(countChip('Keep 0'), findsOneWidget);
    expect(countChip('Delete 0'), findsOneWidget);
  });

  testWidgets('tapping a photo changes what is kept; one must stay', (
    tester,
  ) async {
    await openSimilar(tester, fiveShots());

    // Add IMG_3 (blurred, not picked to start with): keep two.
    await tester.tap(tile('IMG_3.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('Keep 2, mark 1 to delete'), findsOneWidget);

    // Then every one: all are kept.
    await tester.tap(tile('IMG_2.jpg'));
    await tester.pumpAndSettle();
    await tester.tap(tile('IMG_1.jpg'));
    await tester.pumpAndSettle();
    // Whichever were left, tapping each flips it; get to all kept.
    for (final name in ['IMG_1.jpg', 'IMG_2.jpg', 'IMG_3.jpg']) {
      final label = tester.widget<Semantics>(tile(name)).properties.label!;
      if (label.contains('marked to delete')) {
        await tester.tap(tile(name));
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Keep all 3'), findsOneWidget);

    // Take them all off: nothing can be confirmed.
    for (final name in ['IMG_1.jpg', 'IMG_2.jpg', 'IMG_3.jpg']) {
      await tester.tap(tile(name));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pick at least one to keep'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Pick at least one to keep'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pressing and holding looks closer, and Keep or Delete there '
      'picks that photo', (tester) async {
    await openSimilar(tester, fiveShots());
    Finder labelled(String text) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == text,
    );

    // IMG_3 (blurred) starts as not kept. Keep it from the closer look.
    await tester.longPress(tile('IMG_3.jpg'));
    await tester.pumpAndSettle();
    expect(
      find.text('Double-tap for 100%. Pinch to zoom, drag to look around.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(labelled('IMG_3.jpg, keeping'), findsOneWidget);
    expect(find.text('Keep 2, mark 1 to delete'), findsOneWidget);

    // And Delete there takes a photo off again.
    await tester.longPress(tile('IMG_3.jpg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(labelled('IMG_3.jpg, marked to delete'), findsOneWidget);
    expect(find.text('Keep 1, mark 2 to delete'), findsOneWidget);
  });

  testWidgets('skipping a group decides nothing', (tester) async {
    await openSimilar(tester, fiveShots());

    await tester.tap(find.text('Skip this group'));
    await tester.pumpAndSettle();
    expect(
      find.text('You skipped them all, so nothing was decided.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Back to sorting'));
    await tester.pumpAndSettle();
    expect(countChip('Keep 0'), findsOneWidget);
    expect(countChip('Delete 0'), findsOneWidget);
  });

  testWidgets('says so when there are no look-alikes', (tester) async {
    // The default pictures are too small to compare.
    await openSimilar(
      tester,
      FakePhotoRepository(
        photoCounts: {'Camera': 5},
        spacing: const Duration(seconds: 30),
      ),
    );

    expect(find.textContaining('No similar photos found'), findsOneWidget);
  });

  testWidgets('fits a small phone with 200% text', (tester) async {
    // The worst case for layout: if anything doesn't fit, Flutter reports an
    // overflow and the test fails.
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openSimilar(tester, fiveShots());

    expect(find.text('Keep 1, mark 2 to delete'), findsOneWidget);
    await tester.tap(find.text('Keep 1, mark 2 to delete'));
    await tester.pumpAndSettle();
    expect(find.text('All groups done'), findsOneWidget);
  });
}
