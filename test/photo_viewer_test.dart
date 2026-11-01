import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/screens/photo_viewer_screen.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/sort_progress.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

void main() {
  Future<void> openCamera(WidgetTester tester) async {
    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      PhotoSwipeApp(
        repository: FakePhotoRepository(photoCounts: {'Camera': 3}),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
  }

  Future<void> openViewer(WidgetTester tester) async {
    await tester.tap(find.byType(SwipeCard));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsOneWidget);
  }

  double zoomLevel(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the photo opens it; closing goes back', (tester) async {
    await openCamera(tester);
    await openViewer(tester);
    expect(find.text('IMG_1.jpg'), findsOneWidget); // Title.

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(find.text('0 / 3 sorted'), findsOneWidget);
  });

  testWidgets('Keep in the viewer sorts the photo', (tester) async {
    await openCamera(tester);
    await openViewer(tester);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(find.text('1 / 3 sorted'), findsOneWidget);
    expect(find.text('IMG_2.jpg'), findsOneWidget);
  });

  testWidgets('double-tap zooms in, and again zooms back out', (tester) async {
    await openCamera(tester);
    await openViewer(tester);
    expect(zoomLevel(tester), 1);

    await doubleTap(tester, find.byType(InteractiveViewer));
    expect(zoomLevel(tester), greaterThan(2));

    await doubleTap(tester, find.byType(InteractiveViewer));
    expect(zoomLevel(tester), 1);
  });

  // In the viewer a drag means "look around", never "decide": only the
  // buttons decide. Try hard to decide by accident and check nothing did.
  testWidgets('dragging in the viewer never keeps or deletes', (tester) async {
    await openCamera(tester);
    await openViewer(tester);
    final photo = find.byType(InteractiveViewer);

    // Fast flicks at normal size, exactly like a swipe on the card.
    await tester.fling(photo, const Offset(-300, 0), 3000);
    await tester.pumpAndSettle();
    await tester.fling(photo, const Offset(300, 0), 3000);
    await tester.pumpAndSettle();

    // Zoomed in, looking around in every direction.
    await doubleTap(tester, photo);
    expect(zoomLevel(tester), greaterThan(2));
    for (final move in const [
      Offset(-400, 0),
      Offset(400, 0),
      Offset(0, -400),
      Offset(0, 400),
    ]) {
      await tester.fling(photo, move, 3000);
      await tester.pumpAndSettle();
    }

    // A drag that starts on a button is not a press of it.
    await tester.drag(find.text('Delete'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 3 sorted'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget); // Same photo, waiting.
  });

  testWidgets('Escape closes the viewer without deciding', (tester) async {
    await openCamera(tester);
    await openViewer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(find.text('0 / 3 sorted'), findsOneWidget);
  });

  testWidgets('the progress bar shows the keep/delete split', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(
            width: 432, // 400 wide inside the 16 px padding.
            child: SortProgress(sorted: 4, total: 10, kept: 3, deleted: 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double widthOf(Color color) => tester
        .getSize(
          find.byWidgetPredicate((w) => w is ColoredBox && w.color == color),
        )
        .width;
    expect(widthOf(SortColors.light.keep), closeTo(120, 0.5)); // 30%
    expect(widthOf(SortColors.light.delete), closeTo(40, 0.5)); // 10%
  });
}
