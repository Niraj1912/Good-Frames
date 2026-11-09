// Makes a folder of deliberately awkward test photos, so the app can be
// developed without ever touching a real photo library.
//
//   dart run tool/make_test_photos.dart [folder] [--many N]
//
// The default folder is E:\test-photos. --many adds a Bulk folder of N small
// photos, for checking speed with a big library. The script only deletes a
// folder it made itself (one holding a .goodframes-test-photos marker file),
// so it can never wipe someone's real photos by mistake.

import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _marker = '.goodframes-test-photos';

Future<void> main(List<String> args) async {
  var folder = r'E:\test-photos';
  var many = 0;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--many') {
      many = int.parse(args[++i]);
    } else {
      folder = args[i];
    }
  }
  final root = Directory(folder);

  if (await root.exists()) {
    final madeByUs = await File(p.join(root.path, _marker)).exists();
    if (!madeByUs && !await root.list().isEmpty) {
      stderr.writeln(
        '${root.path} has files this script did not make. Not touching it.',
      );
      exitCode = 1;
      return;
    }
    await root.delete(recursive: true);
  }
  await root.create(recursive: true);
  await File(p.join(root.path, _marker))
      .writeAsString('Made by tool/make_test_photos.dart\n');

  final random = Random(42); // Same colors on every run.

  // Ordinary camera photos, landscape and portrait.
  for (var i = 1; i <= 12; i++) {
    final portrait = i % 3 == 0;
    await _writeJpg(
      root,
      'Camera/IMG_${i.toString().padLeft(4, '0')}.jpg',
      _drawPhoto(
        portrait ? 1200 : 1600,
        portrait ? 1600 : 1200,
        'Camera $i',
        random,
      ),
    );
  }

  // A full 24-megapixel photo, to check memory use.
  await _writeJpg(
    root,
    'Camera/IMG_0013_huge.jpg',
    _drawPhoto(6000, 4000, 'Huge photo', random),
  );

  // Stored sideways, with an EXIF tag saying "turn 90 degrees clockwise".
  // It only looks upright if the app honors the tag.
  final upright = _drawPhoto(1200, 1600, 'Should be upright', random);
  final sideways = img.copyRotate(upright, angle: -90)
    ..exif.imageIfd.orientation = 6;
  await _writeJpg(root, 'Camera/IMG_0014_sideways.jpg', sideways);

  // Same file name as a Camera photo, in a different folder.
  await _writeJpg(
    root,
    'Screenshots/IMG_0001.jpg',
    _drawPhoto(1080, 2400, 'Same name as Camera 1', random),
  );
  await _write(
    root,
    'Screenshots/Screenshot_02.png',
    img.encodePng(_drawPhoto(1080, 2400, 'PNG screenshot', random)),
  );

  // A folder name with a space in it.
  for (var i = 1; i <= 3; i++) {
    await _writeJpg(
      root,
      'WhatsApp Images/IMG-20260101-WA000$i.jpg',
      _drawPhoto(1280, 960, 'WhatsApp $i', random),
    );
  }

  // Should show as "Can't display this photo":
  await _write(root, 'Broken/corrupt.jpg', _noise(5000, random));
  await _write(root, 'Broken/empty.jpg', []);
  // Should not show at all:
  await _write(root, 'Broken/photo.heic', _noise(5000, random));
  await _write(root, 'Broken/notes.txt', 'Not a photo.\n'.codeUnits);
  await _write(root, 'Broken/Thumbs.db', [0, 1, 2, 3]);

  // A photo directly in the top folder.
  await _writeJpg(
    root,
    'loose.jpg',
    _drawPhoto(1600, 1200, 'Loose photo', random),
  );

  // Lots of small photos, for checking speed with a big library.
  for (var i = 1; i <= many; i++) {
    await _writeJpg(
      root,
      'Bulk/BULK_${i.toString().padLeft(5, '0')}.jpg',
      _drawPhoto(320, 240, 'Bulk $i', random),
    );
  }

  final files = await root.list(recursive: true).where((e) => e is File).length;
  stdout.writeln('Made $files files in ${root.path}');
}

img.Image _drawPhoto(int width, int height, String label, Random random) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgb8(
      40 + random.nextInt(160),
      40 + random.nextInt(160),
      40 + random.nextInt(160),
    ),
  );
  final white = img.ColorRgb8(255, 255, 255);
  img.drawString(image, label, font: img.arial48, x: 40, y: 40, color: white);
  img.drawString(
    image,
    '$width x $height',
    font: img.arial48,
    x: 40,
    y: 110,
    color: white,
  );
  return image;
}

List<int> _noise(int length, Random random) =>
    List.generate(length, (_) => random.nextInt(256));

Future<void> _writeJpg(Directory root, String path, img.Image image) =>
    _write(root, path, img.encodeJpg(image, quality: 85));

Future<void> _write(Directory root, String path, List<int> bytes) async {
  final file = File(p.joinAll([root.path, ...path.split('/')]));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}
