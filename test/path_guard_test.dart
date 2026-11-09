import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_swipe/data/folder_photo_repository.dart';

void main() {
  late Directory temp;
  late String root;
  late String outside;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('guard');
    root = p.join(temp.path, 'root')..let((d) => Directory(d).createSync());
    outside = p.join(temp.path, 'outside')..let((d) => Directory(d).createSync());
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('accepts a real file inside the folder', () {
    final file = File(p.join(root, 'a.jpg'))..writeAsStringSync('x');
    expect(FolderPhotoRepository.isInside(root, file.path), isTrue);
  });

  test('accepts a file that is not there (already gone)', () {
    expect(FolderPhotoRepository.isInside(root, p.join(root, 'gone.jpg')), isTrue);
  });

  test('rejects paths outside, including ../ tricks', () {
    final file = File(p.join(outside, 'b.jpg'))..writeAsStringSync('x');
    expect(FolderPhotoRepository.isInside(root, file.path), isFalse);
    expect(
      FolderPhotoRepository.isInside(root, p.join(root, '..', 'outside', 'b.jpg')),
      isFalse,
    );
  });

  test('rejects a shortcut inside the folder that leads outside', () {
    File(p.join(outside, 'secret.jpg')).writeAsStringSync('x');
    final link = Link(p.join(root, 'sneaky'));
    try {
      link.createSync(outside);
    } on FileSystemException {
      markTestSkipped('This machine does not allow creating symbolic links.');
      return;
    }
    expect(
      FolderPhotoRepository.isInside(root, p.join(root, 'sneaky', 'secret.jpg')),
      isFalse,
    );
  });
}

extension _Let<T> on T {
  void let(void Function(T) f) => f(this);
}
