import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

void main() {
  Future<void> startApp(
    WidgetTester tester,
    FakePhotoRepository repository,
  ) async {
    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      PhotoSwipeApp(repository: repository, store: store),
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
    expect(find.text('Keep 1  ·  Delete 1'), findsOneWidget);
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
    expect(find.text('Keep 1  ·  Delete 0'), findsOneWidget);

    await tester.fling(find.byType(SwipeCard), const Offset(-80, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Keep 1  ·  Delete 1'), findsOneWidget);
    expect(find.text('IMG_3.jpg'), findsOneWidget);
  });

  testWidgets('shows a summary once every photo is sorted', (tester) async {
    await openCamera(tester);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.text('All sorted!'), findsOneWidget);
    expect(find.text('2 to keep, 1 to delete.'), findsOneWidget);
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
    await tester.tap(find.text('Restore 1 photo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Restored 1 photo.'), findsOneWidget);
    expect(find.textContaining('Nothing here.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 photos'), findsOneWidget); // Back in the album.

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
    expect(find.text('All sorted!'), findsOneWidget);

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
