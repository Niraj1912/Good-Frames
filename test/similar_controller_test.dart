import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/state/similar_controller.dart';
import 'package:good_frames/state/similarity.dart';

import 'fakes/fake_photo_repository.dart';
import 'support/test_images.dart';
import 'support/test_store.dart';

void main() {
  const camera = Album(id: 'Camera', name: 'Camera', photoCount: 5);
  late DecisionStore store;

  setUp(() async => store = await openTestStore());
  tearDown(() => store.close());

  // Five photos, 30 seconds apart: IMG_1, IMG_2 and IMG_3 are the same scene
  // (IMG_2 a little brighter, IMG_3 blurred), IMG_4 and IMG_5 are other
  // scenes. IMG_1 is the newest.
  FakePhotoRepository fiveShots({
    Duration spacing = const Duration(seconds: 30),
  }) {
    return FakePhotoRepository(photoCounts: {'Camera': 5}, spacing: spacing)
      ..images['Camera/1'] = photoPng(1)
      ..images['Camera/2'] = photoPng(1, shift: 15)
      ..images['Camera/3'] = photoPng(1, blurred: true)
      ..images['Camera/4'] = photoPng(2)
      ..images['Camera/5'] = photoPng(3);
  }

  Future<SimilarController> scan(
    WidgetTester tester,
    FakePhotoRepository repository, {
    DecisionStore? using,
  }) async {
    final photos = await repository.allPhotosIn(camera);
    final controller = SimilarController(
      repository: repository,
      store: using ?? store,
      photos: photos,
    );
    addTearDown(controller.dispose);
    // Decoding pictures is real work, so it runs outside the test's clock.
    await tester.runAsync(controller.scan);
    return controller;
  }

  List<String> names(SimilarGroup group) => [
    for (final photo in group.photos) photo.name,
  ];

  testWidgets('finds the look-alikes and leaves the others out', (
    tester,
  ) async {
    final controller = await scan(tester, fiveShots());

    expect(controller.isScanning, isFalse);
    expect(controller.error, isNull);
    // Oldest first: IMG_3 was taken before IMG_2 and IMG_1.
    expect(controller.groups.map(names), [
      ['IMG_3.jpg', 'IMG_2.jpg', 'IMG_1.jpg'],
    ]);
  });

  testWidgets('suggests the sharpest one, not the blurred one', (tester) async {
    final controller = await scan(tester, fiveShots());

    final group = controller.groups.single;
    expect(group.photos[group.suggested].name, isNot('IMG_3.jpg'));
  });

  testWidgets('saves what it learned, and uses it next time', (tester) async {
    await scan(tester, fiveShots());
    expect(await store.loadFingerprints(), hasLength(5));

    // The same photos, but pictures that can't be described: it only finds
    // the group if it used what was saved.
    final second = FakePhotoRepository(
      photoCounts: {'Camera': 5},
      spacing: const Duration(seconds: 30),
    );
    final controller = await scan(tester, second);

    expect(controller.groups, hasLength(1));
    expect(second.imagesRequested, isEmpty);
  });

  testWidgets('works out a fresh fingerprint for a changed photo', (
    tester,
  ) async {
    final repository = fiveShots();
    final photos = await repository.allPhotosIn(camera);
    // A wrong fingerprint for IMG_4, saved against a different date.
    await store.saveFingerprints([
      SavedFingerprint(photos[3].id, 1, const Fingerprint(0, 0.2)),
    ]);

    await scan(tester, repository);

    final saved = (await store.loadFingerprints())[photos[3].id]!;
    expect(saved.stamp, Similarity.stamp(photos[3].date));
    expect(saved.fingerprint.hash, isNot(0));
    expect(repository.imagesRequested, contains(photos[3].id));
  });

  testWidgets('does not open photos that stand alone in time', (tester) async {
    final repository = fiveShots(spacing: const Duration(hours: 1));

    final controller = await scan(tester, repository);

    expect(controller.toLookAt, 0);
    expect(controller.groups, isEmpty);
    expect(repository.imagesRequested, isEmpty);
  });

  testWidgets('reports its progress, ending at all of them', (tester) async {
    final repository = fiveShots();
    final photos = await repository.allPhotosIn(camera);
    final controller = SimilarController(
      repository: repository,
      store: store,
      photos: photos,
    );
    addTearDown(controller.dispose);
    final seen = <int>[];
    controller.addListener(() => seen.add(controller.looked));

    await tester.runAsync(controller.scan);

    expect(controller.toLookAt, 5);
    expect(controller.looked, 5);
    expect(seen, isNotEmpty);
    expect(seen, orderedEquals([...seen]..sort())); // Never goes backwards.
  });

  testWidgets('pictures too small to describe make no group, and no error', (
    tester,
  ) async {
    final controller = await scan(
      tester,
      FakePhotoRepository(
        photoCounts: {'Camera': 5},
        spacing: const Duration(seconds: 30),
      ),
    );

    expect(controller.groups, isEmpty);
    expect(controller.error, isNull);
    expect(controller.isScanning, isFalse);
  });

  testWidgets('a search that cannot save still reports the failure', (
    tester,
  ) async {
    final repository = fiveShots();
    final photos = await repository.allPhotosIn(camera);
    final controller = SimilarController(
      repository: repository,
      store: _FailingStore(store),
      photos: photos,
    );
    addTearDown(controller.dispose);

    await tester.runAsync(controller.scan);

    expect(controller.error, isNotNull);
    expect(controller.isScanning, isFalse);
  });

  testWidgets('a search closed part-way stops quietly', (tester) async {
    final repository = fiveShots();
    final photos = await repository.allPhotosIn(camera);
    final controller = SimilarController(
      repository: repository,
      store: store,
      photos: photos,
    );

    final running = tester.runAsync(controller.scan);
    controller.dispose(); // The screen was closed.
    await running;

    // Nothing to check but that it didn't throw.
  });
}

/// A store that works, except that fingerprints can't be saved.
class _FailingStore implements DecisionStore {
  _FailingStore(this._real);

  final DecisionStore _real;

  @override
  Future<Map<String, SavedFingerprint>> loadFingerprints() =>
      _real.loadFingerprints();

  @override
  Future<void> saveFingerprints(
    Iterable<SavedFingerprint> fingerprints,
  ) async => throw Exception('disk full');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
