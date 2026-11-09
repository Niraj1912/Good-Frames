import 'package:flutter/material.dart';
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/models/photo.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet for [photo], so it can be sent to someone
/// without leaving the sorting screen. Sharing changes nothing: the photo
/// keeps its place in the sort.
Future<void> sharePhoto(
  BuildContext context,
  PhotoRepository repository,
  Photo photo,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void tell(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  try {
    final file = await repository.fileForSharing(photo);
    if (file == null) {
      tell("Couldn't open that photo to share it.");
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  } catch (error) {
    tell("Couldn't share that photo.\n$error");
  }
}
