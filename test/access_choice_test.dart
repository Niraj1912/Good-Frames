import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/main.dart';
import 'package:good_frames/models/chosen_folder.dart';
import 'package:good_frames/state/settings.dart';

import 'fakes/fake_chosen_folders_repository.dart';
import 'fakes/fake_photo_repository.dart';
import 'support/test_store.dart';

// The first-run choice on Android: one folder, or every photo. The fake
// "all photos" source has a Camera album and the fake folder a Holiday one,
// so each test can tell which it's looking at.
void main() {
  const holiday = ChosenFolder(
    uri: 'tree:holiday',
    name: 'Holiday',
    path: 'Pictures/Holiday',
  );

  late FakePhotoRepository allPhotos;
  late FakeChosenFoldersRepository folders;

  setUp(() {
    allPhotos = FakePhotoRepository(access: AccessStatus.denied);
    folders = FakeChosenFoldersRepository();
  });

  Future<void> startApp(WidgetTester tester) async {
    final store = await openTestStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      GoodFramesApp(
        repository: allPhotos,
        folders: folders,
        store: store,
        settings: await Settings.load(store),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing shared yet, asks what Good Frames should see', (
    tester,
  ) async {
    await startApp(tester);

    expect(find.text('What should Good Frames see?'), findsOneWidget);
    expect(find.text('Choose a folder'), findsOneWidget);
    expect(find.text('All photos, or some'), findsOneWidget);
    // Nothing to go back to on first launch.
    expect(find.byTooltip('Cancel'), findsNothing);
  });

  testWidgets('choosing a folder shows only its albums, with a note', (
    tester,
  ) async {
    folders.nextPick = holiday;
    await startApp(tester);

    await tester.tap(find.text('Choose a folder'));
    await tester.pumpAndSettle();

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
    expect(
      find.text('Good Frames can only see the folders you chose.'),
      findsOneWidget,
    );
  });

  testWidgets('backing out of the folder picker stays on the choice', (
    tester,
  ) async {
    await startApp(tester); // nextPick is null: the user backs out.

    await tester.tap(find.text('Choose a folder'));
    await tester.pumpAndSettle();

    expect(find.text('What should Good Frames see?'), findsOneWidget);
  });

  testWidgets('a shared folder is remembered: the app opens straight on it', (
    tester,
  ) async {
    folders.chosen.add(holiday);
    await startApp(tester);

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('What should Good Frames see?'), findsNothing);
  });

  testWidgets('removing the last folder goes back to the choice', (
    tester,
  ) async {
    folders.chosen.add(holiday);
    await startApp(tester);

    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('Pictures/Holiday'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop sharing Holiday'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No folders shared.'), findsOneWidget);
    expect(folders.chosen, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('What should Good Frames see?'), findsOneWidget);
  });

  testWidgets('all photos, once allowed, shows every album', (tester) async {
    await startApp(tester);
    allPhotos.access = AccessStatus.granted; // The user taps Allow.

    await tester.tap(find.text('All photos, or some'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.textContaining('can only see'), findsNothing);
  });

  testWidgets('picking just some photos goes through the same card', (
    tester,
  ) async {
    await startApp(tester);
    // In Android's prompt the user taps "Allow limited access" and picks a
    // few photos.
    allPhotos.access = AccessStatus.limited;

    await tester.tap(find.text('All photos, or some'));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(
      find.text('Good Frames can only see the photos you selected.'),
      findsOneWidget,
    );
    // "Change" reopens Android's picker, to share more photos.
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(allPhotos.selectionChanged, isTrue);
  });

  Future<void> openWhatGoodFramesSees(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    // Settings scrolls now, so bring the row into view first.
    await tester.ensureVisible(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();
  }

  testWidgets('from all photos, Settings can switch to one folder', (
    tester,
  ) async {
    allPhotos.access = AccessStatus.granted;
    folders.nextPick = holiday;
    await startApp(tester);
    expect(find.text('Camera'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('All photos'), findsOneWidget);
    // Settings scrolls now, so bring the row into view first.
    await tester.ensureVisible(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();
    // The first-launch choice again.
    expect(find.text('What should Good Frames see?'), findsOneWidget);
    await tester.tap(find.text('Choose a folder'));
    await tester.pumpAndSettle();

    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
  });

  testWidgets('the choice from Settings can be cancelled, or backed out of', (
    tester,
  ) async {
    allPhotos.access = AccessStatus.granted;
    await startApp(tester);

    await openWhatGoodFramesSees(tester);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);

    // Android's back gesture does the same, rather than closing the app.
    await openWhatGoodFramesSees(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('with photos picked one by one, Settings says so', (
    tester,
  ) async {
    allPhotos.access = AccessStatus.limited;
    await startApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Only photos you selected'), findsOneWidget);
  });

  testWidgets('with a folder shared, Settings names it and opens Folders', (
    tester,
  ) async {
    folders.chosen.add(holiday);
    await startApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Only the Holiday folder'), findsOneWidget);
    // Settings scrolls now, so bring the row into view first.
    await tester.ensureVisible(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What Good Frames sees'));
    await tester.pumpAndSettle();

    expect(find.text('Pictures/Holiday'), findsOneWidget);
  });

  testWidgets('refusing all photos explains, and offers a folder or Settings', (
    tester,
  ) async {
    await startApp(tester); // allPhotos.access stays denied: the user refuses.

    await tester.tap(find.text('All photos, or some'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Android didn't allow access to all photos."),
      findsOneWidget,
    );
    expect(find.text('Choose a folder'), findsOneWidget);
    // Below the fold on a small screen, so scroll to it as a person would.
    await tester.ensureVisible(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    expect(allPhotos.settingsOpened, isTrue);
  });

  testWidgets('someone who already allowed all photos skips the choice', (
    tester,
  ) async {
    allPhotos.access = AccessStatus.granted;
    await startApp(tester);

    expect(find.text('What should Good Frames see?'), findsNothing);
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('"Use all photos instead" stops sharing every folder', (
    tester,
  ) async {
    folders.chosen.add(holiday);
    allPhotos.access = AccessStatus.granted; // Allowed when Android asks.
    await startApp(tester);

    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use all photos instead'));
    await tester.pumpAndSettle();

    expect(folders.chosen, isEmpty);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.textContaining('can only see'), findsNothing);
  });
}
