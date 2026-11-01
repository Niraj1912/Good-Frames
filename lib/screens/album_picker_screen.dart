import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/screens/recently_deleted_screen.dart';
import 'package:photo_swipe/screens/sort_screen.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// Lists the albums so the user can pick which one to sort.
class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({
    super.key,
    required this.repository,
    required this.store,
    this.accessNote,
    this.accessActionLabel = 'Change',
    this.onAccessAction,
    this.onChooseFolder,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  /// A note at the top saying SwipeSort sees only part of the library, such
  /// as only the photos or folders the user chose. Null for none.
  final String? accessNote;

  /// The note's button, and what it does. The albums reload after.
  final String accessActionLabel;
  final Future<void> Function()? onAccessAction;

  /// Offers to look at one folder instead of every photo. Null where that
  /// isn't possible.
  final Future<void> Function()? onChooseFolder;

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

  Future<void> _onAccessAction() async {
    await widget.onAccessAction?.call();
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
          if (widget.onChooseFolder case final chooseFolder?)
            IconButton(
              onPressed: chooseFolder,
              icon: const Icon(Icons.folder_open_outlined),
              tooltip: 'Choose a folder instead',
            ),
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
          if (widget.accessNote case final note?)
            MaterialBanner(
              leading: const Icon(Icons.info_outline),
              content: Text(note),
              actions: [
                TextButton(
                  onPressed: _onAccessAction,
                  child: Text(widget.accessActionLabel),
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
                final width = MediaQuery.sizeOf(context).width;
                // More columns on wider windows, so covers stay a sensible size.
                final columns = width >= 900
                    ? 5
                    : width >= 600
                    ? 3
                    : 2;
                final coverWidth =
                    (width / columns * MediaQuery.devicePixelRatioOf(context))
                        .round();
                return CustomScrollView(
                  slivers: [
                    if (notice != null)
                      SliverToBoxAdapter(
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          subtitle: Text(notice),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: albums.length,
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return _AlbumTile(
                            album: album,
                            cover: switch (album.cover) {
                              final photo? => widget.repository.imageFor(
                                photo,
                                width: coverWidth,
                              ),
                              null => null,
                            },
                            onTap: () => _open(album),
                          );
                        },
                      ),
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

/// One album on the list: its newest photo, its name and how many photos.
class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.cover,
    required this.onTap,
  });

  final Album album;
  final ImageProvider? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Center(
      child: Icon(
        Icons.photo_library_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: SortColors.of(context).photoMatte,
                child: SizedBox.expand(
                  child: switch (cover) {
                    final image? => Image(
                      image: image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => placeholder,
                    ),
                    null => placeholder,
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            photoCount(album.photoCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: AppTheme.tabularFigures,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
