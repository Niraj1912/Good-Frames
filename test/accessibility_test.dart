import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/main.dart';
import 'package:photo_swipe/models/chosen_folder.dart';
import 'package:photo_swipe/state/settings.dart';

import 'fakes/fake_chosen_folders_repository.dart';
import 'fakes/fake_photo_repository.dart';
import 'support/sort_actions.dart';
import 'support/test_store.dart';

// The worst case for layout: a small phone with the text size turned up to
// 200% in the phone's settings, as many people with poor eyesight do. If any
// screen doesn't fit, Flutter reports an overflow and the test fails.
void main() {
  Future<void> startOnSmallPhoneWithBigText(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      PhotoSwipeApp(
        // Two photos from different months, so the month picker shows.
        repository: FakePhotoRepository(
          photoCounts: {'Camera': 2},
          spacing: const Duration(days: 40),
        ),
        store: store,
        settings: await Settings.load(store),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every screen fits with 200% text on a small phone', (
    tester,
  ) async {
    await startOnSmallPhoneWithBigText(tester);

    // Album list, then the sort screen, with the month under its name.
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    // The month picker, then back to every month.
    await tester.tap(find.text('All months'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All months').last);
    await tester.pumpAndSettle();

    // Sort both photos to reach the done screen.
    await swipeLeft(tester);
    await tester.pumpAndSettle();
    await swipeRight(tester);
    await tester.pumpAndSettle();
    expect(find.text('All sorted'), findsOneWidget);

    // Review screen. With text this big the button is below the fold, so
    // scroll to it first, as a user would.
    await tester.ensureVisible(find.text('Review 1 to delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 1 to delete'));
    await tester.pumpAndSettle();

    // Recently deleted screen.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recently deleted'));
    await tester.pumpAndSettle();

    // Settings, and one of its choice dialogs.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swipe directions'));
    await tester.pumpAndSettle();
    expect(find.text('Left keeps, right deletes'), findsOneWidget);
  });

  testWidgets('the folder-or-all-photos choice fits too', (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = await openTestStore();
    addTearDown(store.close);
    final folders = FakeChosenFoldersRepository(
      nextPick: const ChosenFolder(
        uri: 'tree:holiday',
        name: 'Holiday',
        path: 'Pictures/Holiday',
      ),
    );

    await tester.pumpWidget(
      PhotoSwipeApp(
        repository: FakePhotoRepository(access: AccessStatus.denied),
        folders: folders,
        store: store,
        settings: await Settings.load(store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What should Good Frames see?'), findsOneWidget);

    // The folders screen, from the album list's note.
    // With text this big the choices run below the fold, so scroll first.
    await tester.ensureVisible(find.text('Choose a folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a folder'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('Pictures/Holiday'), findsOneWidget);
  });
}
