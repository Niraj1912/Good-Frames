import 'package:flutter/material.dart';

/// Shows one photo as large as fits, or a placeholder if it can't be
/// decoded. Broken files still get shown, because they're good candidates
/// for deleting.
class PhotoFrame extends StatelessWidget {
  const PhotoFrame({super.key, required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Image(
        image: image,
        fit: BoxFit.contain,
        // Keep showing the previous photo until the next one is decoded,
        // instead of flashing an empty frame in between.
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const _BrokenPhoto(),
      ),
    );
  }
}

class _BrokenPhoto extends StatelessWidget {
  const _BrokenPhoto();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 64),
          const SizedBox(height: 12),
          const Text("Can't display this photo"),
          const SizedBox(height: 4),
          Text(
            'It may be damaged or in an unsupported format.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
