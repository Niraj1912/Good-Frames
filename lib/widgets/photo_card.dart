import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/photo_frame.dart';

/// A photo in a quiet frame: a neutral matte where the photo doesn't fill
/// it, a hairline border, and no shadow to compete with the picture.
class PhotoCard extends StatelessWidget {
  const PhotoCard({super.key, required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SortColors.of(context).photoMatte,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: PhotoFrame(image: image),
      ),
    );
  }
}
