import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/album_progress.dart';
import 'package:photo_swipe/screens/recently_deleted_screen.dart';
import 'package:photo_swipe/screens/settings_screen.dart';
import 'package:photo_swipe/screens/sort_screen.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/large_title_bar.dart';
import 'package:photo_swipe/widgets/message_view.dart';
import 'package:photo_swipe/widgets/skeleton.dart';

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
  late Future<_Loaded> _albums = _load();

  // The albums, and how far through each the user has got.
  Future<_Loaded> _load() async {
    final albums = await widget.repository.albums();
    final saved = await widget.store.loadSettings().catchError(
      (Object _) => <String, String>{},
    );
    return (
      albums: albums,
      progress: {
        for (final album in albums)
          album.id: ?AlbumProgress.parse(saved[AlbumProgress.keyFor(album.id)]),
      },
    );
  }

  void _reload() {
    // A block body, not `=>`: the closure must not return the Future.
    setState(() {
      _albums = _load();
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
      // Pulling the list down reloads it, so there's no Reload button.
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 56,
        onRefresh: () async {
          final reloaded = _load();
          setState(() => _albums = reloaded);
          await reloaded.then<void>((_) {}, onError: (_) {});
        },
        child: CustomScrollView(
          // Pulls down even when the albums don't fill the screen.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            LargeTitleBar(
              title: 'Albums',
              actions: [
                IconButton(
                  onPressed: _openRecentlyDeleted,
                  icon: const Icon(Icons.restore_from_trash_outlined),
                  tooltip: 'Recently deleted',
                ),
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                ),
              ],
            ),
            if (widget.accessNote case final note?)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Glass(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(note)),
                        TextButton(
                          onPressed: _onAccessAction,
                          child: Text(widget.accessActionLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ..._buildAlbums(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAlbums(BuildContext context) {
    return [
      FutureBuilder(
        future: _albums,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView('Could not load albums.\n${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const SliverToBoxAdapter(child: AlbumListSkeleton());
          }
          final (:albums, :progress) = snapshot.data!;
          if (albums.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                'No photos found in ${widget.repository.sourceName}.',
              ),
            );
          }
          final notice = widget.repository.notice;
          final width = MediaQuery.sizeOf(context).width;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final theme = Theme.of(context);

          // The album the user is in the middle of, if there is one: the
          // one sorted in most recently that still has photos to go.
          Album? resume;
          for (final album in albums) {
            final done = progress[album.id];
            if (done == null || done.sorted == 0) continue;
            if (done.sorted >= album.photoCount) continue;
            if (resume == null ||
                done.openedAt.isAfter(progress[resume.id]!.openedAt)) {
              resume = album;
            }
          }
          final resuming = resume;
          final others = [
            for (final album in albums)
              if (album != resuming) album,
          ];

          return SliverMainAxisGroup(
            slivers: [
              if (notice != null)
                SliverToBoxAdapter(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    subtitle: Text(notice),
                  ),
                ),
              if (resuming != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _ContinueCard(
                      album: resuming,
                      progress: progress[resuming.id]!,
                      cover: resuming.cover == null
                          ? null
                          : widget.repository.imageFor(
                              resuming.cover!,
                              width: (width * dpr).round(),
                            ),
                      onTap: () => _open(resuming),
                    ),
                  ),
                ),
              if (resuming != null && others.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 16, 8),
                    child: Text(
                      'Other albums',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  resuming == null ? 4 : 0,
                  16,
                  24,
                ),
                sliver: SliverToBoxAdapter(
                  child: Glass(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          for (final (i, album) in others.indexed) ...[
                            if (i > 0)
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                indent: 82,
                                color: theme.colorScheme.outlineVariant,
                              ),
                            _AlbumRow(
                              album: album,
                              share: progress[album.id]?.shareOf(
                                album.photoCount,
                              ),
                              cover: album.cover == null
                                  ? null
                                  : widget.repository.imageFor(
                                      album.cover!,
                                      width: (120 * dpr).round(),
                                    ),
                              onTap: () => _open(album),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ];
  }
}

/// The albums, and what's known of the user's progress in each.
typedef _Loaded = ({List<Album> albums, Map<String, AlbumProgress> progress});

/// The album the user was in the middle of: its newest photo, how many are
/// left, a row of ticks for the share kept, deleted and still to do, and the
/// way back in.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.album,
    required this.progress,
    required this.cover,
    required this.onTap,
  });

  final Album album;
  final AlbumProgress progress;
  final ImageProvider? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sort = SortColors.of(context);
    final left = (album.photoCount - progress.sorted).clamp(
      0,
      album.photoCount,
    );
    return Glass(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      padding: const EdgeInsets.all(8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: sort.photoMatte),
                      if (cover case final image?)
                        Image(
                          image: image,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x9E121315),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              album.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick up where you stopped',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatCount(left)} of ${photoCount(album.photoCount)} '
                      'left in ${album.name}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Ticks(
                      kept: progress.kept,
                      deleted: progress.deleted,
                      total: album.photoCount,
                      keepColour: sort.keep,
                      deleteColour: sort.delete,
                      emptyColour: theme.colorScheme.onSurface.withValues(
                        alpha: 0.16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Looks like a button; the whole card is the tap target.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            'Continue sorting',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
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

/// A row of upright ticks: green for the share kept, red for the share
/// deleted, then grey for what's left. Like the marks along a ruler, it says
/// how far through at a glance.
class _Ticks extends StatelessWidget {
  const _Ticks({
    required this.kept,
    required this.deleted,
    required this.total,
    required this.keepColour,
    required this.deleteColour,
    required this.emptyColour,
  });

  final int kept;
  final int deleted;
  final int total;
  final Color keepColour;
  final Color deleteColour;
  final Color emptyColour;

  static const _count = 36;

  @override
  Widget build(BuildContext context) {
    final keptTicks = total == 0 ? 0 : (kept / total * _count).round();
    final deletedTicks = total == 0 ? 0 : (deleted / total * _count).round();
    return ExcludeSemantics(
      child: SizedBox(
        height: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _count; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: FractionallySizedBox(
                  heightFactor: i < keptTicks + deletedTicks ? 1 : 0.55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i < keptTicks
                          ? keepColour
                          : i < keptTicks + deletedTicks
                          ? deleteColour
                          : emptyColour,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One album on the list: a small cover, its name and size, and how much of
/// it is sorted.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.share,
    required this.cover,
    required this.onTap,
  });

  final Album album;

  /// How much is sorted, 0 to 1, or null if the album hasn't been opened.
  final double? share;
  final ImageProvider? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = this.share;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: SortColors.of(context).photoMatte,
                  child: cover == null
                      ? Icon(
                          Icons.photo_library_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Image(
                          image: cover!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
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
            if (share != null && share > 0)
              share >= 1
                  ? Icon(
                      Icons.check_circle_outline,
                      color: SortColors.of(context).keep,
                      semanticLabel: 'All sorted',
                    )
                  : Text(
                      '${(share * 100).floor()}%',
                      style: AppTheme.edgePrint.copyWith(
                        fontSize: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}
