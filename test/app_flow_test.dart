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
    expect(find.text('Nothing has been deleted yet.'), findsOneWidget);
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
