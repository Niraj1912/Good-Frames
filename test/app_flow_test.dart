import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/widgets/photo_card.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

// The keep or delete count above the photo, such as "Keep 2".
Finder countChip(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  Future<void> startApp(
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
  }

  Future<void> openCamera(WidgetTester tester) async {
    await startApp(tester, FakePhotoRepository(photoCounts: {'Camera': 3}));
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the albums once access is granted', (tester) async {
    await startApp(
      tester,
      FakePhotoRepository(photoCounts: {'Camera': 3, 'Screenshots': 1}),
    );

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);
  });

  testWidgets('explains a refusal and lets the user try again', (tester) async {
    final repository = FakePhotoRepository(access: AccessStatus.denied);
    await startApp(tester, repository);

    expect(find.text('SwipeSort needs your photos'), findsOneWidget);

    repository.access = AccessStatus.granted;
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('checks again after the user comes back from Settings', (
    tester,
  ) async {
    final repository = FakePhotoRepository(access: AccessStatus.denied);
    await startApp(tester, repository);

    await tester.tap(find.text('Open settings'));
    expect(repository.settingsOpened, isTrue);

    // The user allows access in the Settings app, then switches back.
    repository.access = AccessStatus.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('offers to change the selection when access is limited', (
    tester,
  ) async {
    final repository = FakePhotoRepository(access: AccessStatus.limited);
    await startApp(tester, repository);

    expect(
      find.text('SwipeSort can only see the photos you selected.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Change'));
    expect(repository.selectionChanged, isTrue);
  });

  testWidgets('says so when there are no photos', (tester) async {
    await startApp(tester, FakePhotoRepository(photoCounts: {}));

    expect(find.text('No photos found in the fake gallery.'), findsOneWidget);
  });

  testWidgets('sorts with the buttons and keys, and can undo', (tester) async {
    await openCamera(tester);

    expect(find.text('0 / 3 sorted'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 sorted'), findsOneWidget);
    expect(find.text('IMG_2.jpg'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(countChip('Keep 1'), findsOneWidget);
    expect(countChip('Delete 1'), findsOneWidget);
    expect(find.text('IMG_3.jpg'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 sorted'), findsOneWidget);
    expect(find.text('IMG_2.jpg'), findsOneWidget);
  });

  testWidgets('dragging or flicking the card sorts the photo', (tester) async {
    await openCamera(tester);

    await tester.drag(find.byType(SwipeCard), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(countChip('Keep 1'), findsOneWidget);
    expect(countChip('Delete 0'), findsOneWidget);

    await tester.fling(find.byType(SwipeCard), const Offset(-80, 0), 2000);
    await tester.pumpAndSettle();
    expect(countChip('Keep 1'), findsOneWidget);
    expect(countChip('Delete 1'), findsOneWidget);
    expect(find.text('IMG_3.jpg'), findsOneWidget);
  });

  testWidgets('while dragging, the button it will press grows', (tester) async {
    await openCamera(tester);
    double deleteScale() => tester
        .widget<AnimatedScale>(
          find.ancestor(
            of: find.text('Delete'),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCard)),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(deleteScale(), greaterThan(1));

    // Let go: the photo is marked, and the button goes back to its size.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(countChip('Delete 1'), findsOneWidget);
    expect(deleteScale(), 1);
  });

  testWidgets('the next photo stays hidden until the card is dragged', (
    tester,
  ) async {
    await openCamera(tester);
    // The photo behind is the first card in the pile.
    double behindOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(PhotoCard).first,
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(behindOpacity(), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCard)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(360, 0));
    await tester.pump();
    expect(behindOpacity(), 1);

    // Once it's at the front, the photo after it waits out of sight.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('IMG_2.jpg'), findsOneWidget);
    expect(behindOpacity(), 0);
  });

  testWidgets('a photo put off comes back once the rest are sorted', (
    tester,
  ) async {
    await openCamera(tester);

    // The button puts it off, and Undo brings it straight back.
    await tester.tap(find.byTooltip('Decide later'));
    await tester.pumpAndSettle();
    expect(find.text('IMG_2.jpg'), findsOneWidget);
    expect(countChip('Later 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(countChip('Later 1'), findsNothing);

    // Swiping up and the up arrow do the same.
    await tester.drag(find.byType(SwipeCard), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('IMG_3.jpg'), findsOneWidget);
    expect(countChip('Later 2'), findsOneWidget);
    expect(find.text('0 / 3 sorted'), findsOneWidget); // Not decisions.

    // Once the rest are sorted, they come back in the order they went.
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(countChip('Later 1'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('IMG_2.jpg'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('All sorted'), findsOneWidget);
  });

  testWidgets('putting off the last photo brings it straight back', (
    tester,
  ) async {
    await startApp(tester, FakePhotoRepository(photoCounts: {'Camera': 1}));
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    final middle = tester.getCenter(find.byType(PhotoCard));

    await tester.tap(find.byTooltip('Decide later'));
    await tester.pumpAndSettle();

    // Nothing else to sort, so it's next again, back in the middle.
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(tester.getCenter(find.byType(PhotoCard)), middle);
  });

  testWidgets('shows a summary once every photo is sorted', (tester) async {
    await openCamera(tester);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.text('All sorted'), findsOneWidget);
    expect(find.bySemanticsLabel('2 to keep'), findsOneWidget);
    expect(find.bySemanticsLabel('1 to delete'), findsOneWidget);
    expect(find.text('Nothing is deleted until you review them.'), findsOne);
    expect(find.text('Review 1 to delete'), findsOneWidget);
  });

  testWidgets('reviews the marked photos, rescues one, trashes the rest', (
    tester,
  ) async {
    final repository = FakePhotoRepository(photoCounts: {'Camera': 3});
    await startApp(tester, repository);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    for (final button in ['Delete', 'Delete', 'Keep']) {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Review 2 to delete'));
    await tester.pumpAndSettle();
    expect(find.text('Move 2 photos to the trash'), findsOneWidget);

    // Changed my mind about IMG_1.
    await tester.tap(find.byKey(const ValueKey('Camera/1')));
    await tester.pumpAndSettle();
    expect(find.text('Move 1 photo to the trash'), findsOneWidget);

    await tester.tap(find.text('Move 1 photo to the trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to trash'));
    await tester.pumpAndSettle();

    expect(repository.trashed, ['Camera/2']);
    expect(find.textContaining('Moved 1 photo to the trash.'), findsOneWidget);
    // Back on the sort screen, with the trashed photo gone.
    expect(find.text('2 / 2 sorted'), findsOneWidget);

    // Let the message time out so the test ends cleanly.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a trashed photo can be restored from Recently deleted', (
    tester,
  ) async {
    final repository = FakePhotoRepository(photoCounts: {'Camera': 2});
    await startApp(tester, repository);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review photos to delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move 1 photo to the trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to trash'));
    await tester.pumpAndSettle();
    await tester.pageBack(); // To the album list.
    await tester.pumpAndSettle();
    expect(find.text('1 photo'), findsOneWidget);

    await tester.tap(find.byTooltip('Recently deleted'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Camera/1')));
    await tester.pumpAndSettle();
    expect(find.text('1 photo chosen'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Restored 1 photo.'), findsOneWidget);
    expect(find.textContaining('Nothing here.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 photos'), findsOneWidget); // Back in the album.

    await tester.pump(const Duration(seconds: 10)); // Let messages time out.
  });

  testWidgets('deleting forever warns first, and Cancel erases nothing', (
    tester,
  ) async {
    final repository = FakePhotoRepository(photoCounts: {'Camera': 2});
    await startApp(tester, repository);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review photos to delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move 1 photo to the trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to trash'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recently deleted'));
    await tester.pumpAndSettle();

    // Nothing chosen yet: both buttons are off.
    final deleteForever = find.widgetWithText(FilledButton, 'Delete forever');
    expect(tester.widget<FilledButton>(deleteForever).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('Camera/1')));
    await tester.pumpAndSettle();
    await tester.tap(deleteForever);
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 photo forever?'), findsOneWidget);

    // Changing your mind is free.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.erased, isEmpty);
    expect(find.byKey(const ValueKey('Camera/1')), findsOneWidget);

    // Meaning it erases the photo.
    await tester.tap(deleteForever);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete forever'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.erased, ['Camera/1']);
    expect(find.textContaining('Deleted 1 photo forever.'), findsOneWidget);
    expect(find.textContaining('Nothing here.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10)); // Let messages time out.
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    final repository = FakePhotoRepository(photoCounts: {'Camera': 2});
    await startApp(tester, repository);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Review halfway through, from the button in the top bar.
    await tester.tap(find.byTooltip('Review photos to delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move 1 photo to the trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.trashed, isEmpty);
    expect(find.text('Move 1 photo to the trash'), findsOneWidget);
  });

  testWidgets('keys still work after clicking a button that disappears', (
    tester,
  ) async {
    await openCamera(tester);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(find.text('All sorted'), findsOneWidget);

    // "Undo last" is replaced by the card as soon as it's clicked.
    await tester.tap(find.text('Undo last'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3 sorted'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3 sorted'), findsOneWidget);
  });

  testWidgets('asks before starting over', (tester) async {
    await openCamera(tester);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Start over'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3 sorted'), findsOneWidget);

    await tester.tap(find.byTooltip('Start over'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 3 sorted'), findsOneWidget);
  });
}
