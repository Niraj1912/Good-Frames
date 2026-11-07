import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/screens/recently_deleted_screen.dart';
import 'package:photo_swipe/screens/settings_screen.dart';
import 'package:photo_swipe/screens/sort_screen.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/theme/photo_tint.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// Lists the albums so the user can pick which one to sort.
class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.settings,
    this.accessNote,
    this.accessActionLabel = 'Change',
    this.onAccessAction,
    this.photos,
  });

  final PhotoRepository repository;
  final DecisionStore store;
  final Settings settings;

  /// A note at the top saying Good Frames sees only part of the library, such
  /// as only the photos or folders the user chose. Null for none.
  final String? accessNote;

  /// The note's button, and what it does. The albums reload after.
  final String accessActionLabel;
  final Future<void> Function()? onAccessAction;

  /// What Good Frames sees, shown in Settings with a way to change it. Null
  /// where there's no choice.
  final PhotoSource? photos;

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
          settings: widget.settings,
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsScreen(settings: widget.settings, photos: widget.photos),
      ),
    );
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
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
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
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        itemCount: albums.length,
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          final cover = album.cover;
                          return _AlbumTile(
                            album: album,
                            cover: cover == null
                                ? null
                                : widget.repository.imageFor(
                                    cover,
                                    width: coverWidth,
                                  ),
                            tintSample: cover == null
                                ? null
                                : () => widget.repository.imageFor(
                                    cover,
                                    width: PhotoTint.sampleWidth,
                                  ),
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

/// One album on the list: a pane of glass tinted with its cover's colour,
/// holding its newest photo, then its name and how many photos. So each
/// album has a colour of its own that comes from its photos.
class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.cover,
    required this.tintSample,
    required this.onTap,
  });

  final Album album;
  final ImageProvider? cover;

  /// A tiny copy of the cover to find its colour from, or null for none.
  final ImageProvider Function()? tintSample;

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
    final sample = tintSample;
    final plain = GlassColors.of(context).fill;

    return PhotoTintBuilder(
      id: album.cover?.id,
      sample: () => sample?.call(),
      // The tint fades in once the cover's colour is found.
      builder: (context, seed) => TweenAnimationBuilder(
        tween: ColorTween(
          begin: plain,
          end: seed == null
              ? plain
              : PhotoTint.panel(
                  seed,
                  theme.brightness,
                ).withValues(alpha: AppTheme.tintedGlass),
        ),
        duration: const Duration(milliseconds: 300),
        builder: (context, tint, child) => Glass(tint: tint, child: child!),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // Set into the glass with a narrow margin, like a print
                  // behind a pane.
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: ColoredBox(
                        color: SortColors.of(context).photoMatte,
                        child: switch (cover) {
                          final image? => Image(
                            image: image,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                placeholder,
                          ),
                          null => placeholder,
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
