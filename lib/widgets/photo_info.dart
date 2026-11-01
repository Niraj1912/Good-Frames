import 'package:flutter/material.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/widgets/formatting.dart';

/// File name, date and size, shown under the photo.
class PhotoInfo extends StatelessWidget {
  const PhotoInfo({super.key, required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = [
      formatDate(photo.date),
      if (photo.sizeBytes != null) formatSize(photo.sizeBytes!),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text(
            photo.name,
            style: textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(details, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
