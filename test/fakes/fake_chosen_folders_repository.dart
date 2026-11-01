import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/chosen_folder.dart';

import 'fake_photo_repository.dart';

/// Photos from folders the test "picks". [nextPick] plays the user in the
/// system's folder picker: the folder they choose, or null for backing out.
class FakeChosenFoldersRepository extends FakePhotoRepository
    implements ChosenFoldersRepository {
  FakeChosenFoldersRepository({
    super.photoCounts = const {'Holiday': 2},
    this.nextPick,
  });

  ChosenFolder? nextPick;

  /// Folders shared so far, oldest first.
  final chosen = <ChosenFolder>[];

  @override
  Future<List<ChosenFolder>> chosenFolders() async => chosen.reversed.toList();

  @override
  Future<ChosenFolder?> chooseFolder() async {
    final folder = nextPick;
    if (folder != null && !chosen.any((f) => f.uri == folder.uri)) {
      chosen.add(folder);
    }
    return folder;
  }

  @override
  Future<void> forgetFolder(ChosenFolder folder) async {
    chosen.removeWhere((f) => f.uri == folder.uri);
  }

  // Access comes from picking folders, never from a prompt.
  @override
  Future<AccessStatus> requestAccess() => checkAccess();

  @override
  Future<AccessStatus> checkAccess() async =>
      chosen.isEmpty ? AccessStatus.denied : AccessStatus.granted;
}
