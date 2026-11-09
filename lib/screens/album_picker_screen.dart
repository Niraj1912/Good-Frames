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

/// The album the user was in the middle of, drawn as a print being
/// developed: the part of the cover that's been sorted is in full colour, the
/// rest is dimmed and grey, and the seam between them glows in the accent. A pane of frosted glass at the bottom
/// holds how many are left and the way back in.
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

  static const _height = 264.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sort = SortColors.of(context);
    final glass = GlassColors.of(context);
    final left = (album.photoCount - progress.sorted).clamp(
      0,
      album.photoCount,
    );
    final share = progress.shareOf(album.photoCount);
    final percent = (share * 100).floor();
    // The seam never touches an edge, so it and its tag stay in view.
    final seamAt = share.clamp(0.08, 0.92);
    final still = MediaQuery.disableAnimationsOf(context);
    final bigText = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pick up where you stopped',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '${formatCount(left)} left',
          style: theme.textTheme.titleLarge?.copyWith(
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        Text(
          'in ${album.name} · ${formatCount(progress.kept)} kept · '
          '${formatCount(progress.deleted)} deleted',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: AppTheme.tabularFigures,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    // Looks like a button; the whole card is the tap target.
    final button = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Text(
          'Continue',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          'Continue sorting ${album.name}. ${formatCount(left)} photos left, '
          '$percent% sorted',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: _height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: sort.photoMatte),
                  // The seam sweeps out from the left edge once, as the card
                  // arrives, to show how far you've got.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: still ? seamAt : 0, end: seamAt),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (context, at, _) => _Developing(
                      cover: cover,
                      at: at,
                      percent: at / seamAt * percent,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Glass(
                      blur: true,
                      tint: glass.overPhotos,
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.all(12),
                      child: bigText
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                texts,
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: button,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: texts),
                                const SizedBox(width: 8),
                                button,
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cover split at [at] (0 to 1 across): colour to the left, dimmed grey
/// to the right, with a glowing seam and a percentage tag where they meet.
class _Developing extends StatelessWidget {
  const _Developing({
    required this.cover,
    required this.at,
    required this.percent,
  });

  final ImageProvider? cover;
  final double at;
  final double percent;

  // The accent teal, in its light form: fixed in both themes, because the
  // seam sits on a photo, not on paper.
  static const _seam = [Color(0xFF82C8BC), Color(0xFF82C8BC)];

  // Grey, and a little under half as bright.
  static const _grey = ColorFilter.matrix(<double>[
    0.12, 0.39, 0.04, 0, 0, //
    0.12, 0.39, 0.04, 0, 0,
    0.12, 0.39, 0.04, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final image = cover;
    return LayoutBuilder(
      builder: (context, box) {
        final x = box.maxWidth * at;
        Widget photo() => Image(
          image: image!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (image != null) ...[
              photo(),
              ClipRect(
                clipper: _RightOf(at),
                child: ColorFiltered(colorFilter: _grey, child: photo()),
              ),
            ],
            // The glow: the accent, fading out to either side of the seam.
            Positioned(
              left: x - 30,
              width: 60,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0xF2FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ).createShader(bounds),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _seam,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: x - 0.75,
              width: 1.5,
              top: 0,
              bottom: 0,
              child: const ColoredBox(color: Color(0xFF82C8BC)),
            ),
            Positioned(
              left: x,
              top: 14,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xC9FFFFFF)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    child: Text(
                      '${percent.round()}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF17242A),
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keeps what's right of [at] (0 to 1 across) and cuts the rest.
class _RightOf extends CustomClipper<Rect> {
  const _RightOf(this.at);

  final double at;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width * at, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightOf oldClipper) => oldClipper.at != at;
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
