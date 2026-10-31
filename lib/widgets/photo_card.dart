import 'package:flutter/material.dart';
import 'package:photo_swipe/widgets/photo_frame.dart';

/// A photo on a rounded, raised card: the thing the user swipes.
class PhotoCard extends StatelessWidget {
  const PhotoCard({super.key, required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: PhotoFrame(image: image),
    );
  }
}
