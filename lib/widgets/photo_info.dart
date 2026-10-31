import 'package:flutter/material.dart';
import 'package:photo_swipe/models/photo.dart';

/// File name, date and size, shown under the photo.
class PhotoInfo extends StatelessWidget {
  const PhotoInfo({super.key, required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = [
      _formatDate(photo.date),
      if (photo.sizeBytes != null) _formatSize(photo.sizeBytes!),
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

String _formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
