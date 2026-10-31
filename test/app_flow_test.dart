import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/main.dart';

import 'fakes/fake_photo_repository.dart';

void main() {
  Future<void> startApp(
    WidgetTester tester,
    FakePhotoRepository repository,
  ) async {
    await tester.pumpWidget(PhotoSwipeApp(repository: repository));
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

  testWidgets('steps through photos with the buttons and arrow keys', (
    tester,
  ) async {
    await startApp(tester, FakePhotoRepository(photoCounts: {'Camera': 3}));
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    // Already on the last photo, so going further does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
