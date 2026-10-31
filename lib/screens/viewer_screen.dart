import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/widgets/message_view.dart';
import 'package:photo_swipe/widgets/photo_frame.dart';
import 'package:photo_swipe/widgets/photo_info.dart';

/// Shows an album's photos one at a time, with Previous and Next.
/// Read-only: nothing here can change or delete a photo.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.repository,
    required this.album,
  });

  final PhotoRepository repository;
  final Album album;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final Future<List<Photo>> _photos = widget.repository.photosIn(
    widget.album,
  );
  int _index = 0;

  void _move(int step, int count) {
    final next = _index + step;
    if (next >= 0 && next < count) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: FutureBuilder(
        future: _photos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MessageView('Could not load photos.\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final photos = snapshot.data!;
          if (photos.isEmpty) return const MessageView('This album is empty.');
          return _buildViewer(context, photos);
        },
      ),
    );
  }

  Widget _buildViewer(BuildContext context, List<Photo> photos) {
    final photo = photos[_index];
    final count = photos.length;
    // Decode at the screen's real pixel width, not the photo's full size.
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    // The arrow keys do the same as the buttons, for the Windows build.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _move(-1, count),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _move(1, count),
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PhotoFrame(
                  image: widget.repository.imageFor(photo, width: width),
                ),
              ),
              PhotoInfo(photo: photo),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _index > 0 ? () => _move(-1, count) : null,
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous',
                    ),
                    Text(
                      '${_index + 1} / $count',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton.filledTonal(
                      onPressed: _index < count - 1
                          ? () => _move(1, count)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
