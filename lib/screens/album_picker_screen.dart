import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/screens/recently_deleted_screen.dart';
import 'package:photo_swipe/screens/sort_screen.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// Lists the albums so the user can pick which one to sort.
class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({
    super.key,
    required this.repository,
    required this.store,
    this.limitedAccess = false,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  /// True when the user shared only some photos (Android 14+).
  final bool limitedAccess;

  @override
  State<AlbumPickerScreen> createState() => _AlbumPickerScreenState();
}

class _AlbumPickerScreenState extends State<AlbumPickerScreen> {
  late Future<List<Album>> _albums = widget.repository.albums();

  void _reload() {
    // A block body, not `=>`: the closure must not return the Future.
    setState(() {
      _albums = widget.repository.albums();
    });
  }

  Future<void> _changeSelectedPhotos() async {
    await widget.repository.changeSelectedPhotos();
    if (mounted) _reload();
  }

  Future<void> _open(Album album) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SortScreen(
          repository: widget.repository,
          store: widget.store,
          album: album,
        ),
      ),
    );
    // Photos may have been moved to the trash, so the counts are stale.
    if (mounted) _reload();
  }

  Future<void> _openRecentlyDeleted() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecentlyDeletedScreen(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
    // Restored photos are back in their albums.
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose an album'),
        actions: [
          IconButton(
            onPressed: _openRecentlyDeleted,
            icon: const Icon(Icons.restore_from_trash_outlined),
            tooltip: 'Recently deleted',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.limitedAccess)
            MaterialBanner(
              leading: const Icon(Icons.info_outline),
              content: const Text(
                'SwipeSort can only see the photos you selected.',
              ),
              actions: [
                TextButton(
                  onPressed: _changeSelectedPhotos,
                  child: const Text('Change'),
                ),
              ],
            ),
          Expanded(
            child: FutureBuilder(
              future: _albums,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return MessageView(
                    'Could not load albums.\n${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final albums = snapshot.data!;
                if (albums.isEmpty) {
                  return MessageView(
                    'No photos found in ${widget.repository.sourceName}.',
                  );
                }
                final notice = widget.repository.notice;
                return ListView(
                  children: [
                    if (notice != null)
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        subtitle: Text(notice),
                      ),
                    for (final album in albums)
                      ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: Text(album.name),
                        subtitle: Text(photoCount(album.photoCount)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(album),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
