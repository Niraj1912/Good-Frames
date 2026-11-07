import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/models/keep_side.dart';
import 'package:photo_swipe/models/photo_order.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/broken_store.dart';
import 'support/sort_actions.dart';
import 'support/test_store.dart';

// The keep or delete count above the photo, such as "Keep 2".
Finder countChip(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  group('saved settings', () {
    test('start with the defaults', () async {
      final store = await openTestStore();
      addTearDown(store.close);

      final settings = await Settings.load(store);

      expect(settings.keepSide, KeepSide.right);
      expect(settings.order, PhotoOrder.newestFirst);
      expect(settings.vibration, isTrue);
      expect(settings.theme, ThemeMode.system);
    });

    test('come back the next time the app opens', () async {
      final store = await openTestStore();
      addTearDown(store.close);
      final settings = await Settings.load(store);
      await settings.setKeepSide(KeepSide.left);
      await settings.setOrder(PhotoOrder.oldestFirst);
      await settings.setVibration(false);
      await settings.setTheme(ThemeMode.dark);

      final reopened = await Settings.load(store);

      expect(reopened.keepSide, KeepSide.left);
      expect(reopened.order, PhotoOrder.oldestFirst);
      expect(reopened.vibration, isFalse);
      expect(reopened.theme, ThemeMode.dark);
    });

    test("one this version doesn't understand gets its default", () async {
      final store = await openTestStore();
      addTearDown(store.close);
      // As if a newer version had saved an order this one doesn't have.
      await store.saveSetting('order', 'biggestFirst');

      expect((await Settings.load(store)).order, PhotoOrder.newestFirst);
    });

    test("a change that can't be saved still applies for now", () async {
      final settings = await Settings.load(BrokenStore());

      await expectLater(
        settings.setOrder(PhotoOrder.oldestFirst),
        throwsException,
      );
      expect(settings.order, PhotoOrder.oldestFirst);
    });
  });

  Future<void> startApp(WidgetTester tester) async {
    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      PhotoSwipeApp(
        repository: FakePhotoRepository(photoCounts: {'Camera': 3}),
        store: store,
        settings: await Settings.load(store),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  // Taps a setting, then one of the choices in its dialog.
  Future<void> choose(
    WidgetTester tester,
    String setting,
    String choice,
  ) async {
    await tester.tap(find.text(setting));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
  }

  // Back from Settings to the album list, then into Camera.
  Future<void> openCamera(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
  }

  testWidgets('the gear opens Settings, showing each choice', (tester) async {
    await startApp(tester);
    await openSettings(tester);

    expect(find.text('Right keeps, left deletes'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);
    expect(find.text('Same as phone'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    // Nothing to choose between on this photo source (like Windows), and
    // no version without Android to ask.
    expect(find.text('What Good Frames sees'), findsNothing);
    expect(find.text('Version'), findsNothing);
  });

  testWidgets('swapped swipe directions swap the hint and the swipes', (
    tester,
  ) async {
    await startApp(tester);
    await openSettings(tester);

    await choose(tester, 'Swipe directions', 'Left keeps, right deletes');
    expect(find.text('Left keeps, right deletes'), findsOneWidget);
    await openCamera(tester);

    // The hint under the photo follows: Keep on the left, Delete on the right.
    expect(
      tester.getCenter(find.text('Keep')).dx,
      lessThan(tester.getCenter(find.text('Delete')).dx),
    );
    // Dragging right now deletes...
    await tester.drag(find.byType(SwipeCard), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(countChip('Keep 0'), findsOneWidget);
    expect(countChip('Delete 1'), findsOneWidget);
    // ...and swiping left keeps it.
    await swipeLeft(tester);
    await tester.pumpAndSettle();
    expect(countChip('Keep 1'), findsOneWidget);
    expect(countChip('Delete 1'), findsOneWidget);
    // The arrow keys follow the swipes: right deletes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('All sorted'), findsOneWidget);
    expect(find.bySemanticsLabel('1 to keep'), findsOneWidget);
    expect(find.bySemanticsLabel('2 to delete'), findsOneWidget);
  });

  testWidgets('oldest first starts with the oldest photo', (tester) async {
    await startApp(tester);
    await openSettings(tester);

    await choose(tester, 'Order', 'Oldest first');
    await openCamera(tester);

    expect(showing('IMG_3.jpg'), findsOneWidget); // The fake's oldest.
  });

  testWidgets('the theme changes at once', (tester) async {
    await startApp(tester);
    await openSettings(tester);

    await choose(tester, 'Theme', 'Dark');
    expect(
      Theme.of(tester.element(find.text('Theme'))).brightness,
      Brightness.dark,
    );

    await choose(tester, 'Theme', 'Light');
    expect(
      Theme.of(tester.element(find.text('Theme'))).brightness,
      Brightness.light,
    );
  });

  testWidgets('with vibration off, swiping never buzzes', (tester) async {
    var buzzes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') buzzes++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await startApp(tester);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    // The arrow key swipes without the drag's own click at the threshold.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(buzzes, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tester.tap(find.text('Vibration'));
    await tester.pumpAndSettle();
    await openCamera(tester);
    // The arrow key swipes without the drag's own click at the threshold.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(buzzes, 1);
  });

  testWidgets('shows the version Android reports, and the licences', (
    tester,
  ) async {
    const app = MethodChannel('swipesort/app');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      app,
      (call) async => call.method == 'version' ? '1.0.0 (1)' : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        app,
        null,
      ),
    );
    await startApp(tester);
    await openSettings(tester);

    expect(find.text('1.0.0 (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('Open-source licenses'));
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
