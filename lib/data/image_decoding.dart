import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Decodes [provider] once, through Flutter's image cache, and hands back
/// its own copy of the result: the caller must [ui.Image.dispose] it.
/// Fails with whatever error the provider reports, such as a file that
/// isn't a picture.
Future<ui.Image> decodeImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
