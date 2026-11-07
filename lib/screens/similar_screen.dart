import 'package:flutter/material.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/keep_side.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/screens/photo_viewer_screen.dart';
import 'package:photo_swipe/state/similar_controller.dart';
import 'package:photo_swipe/state/sort_controller.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// Photos that look alike, a group at a time: shots of the same thing taken
/// moments apart. The one that looks sharpest is picked to keep; tap any to
/// change that (or to keep two), then confirm. The rest are only marked to
/// delete: like everywhere else, nothing is deleted until the Review screen.
class SimilarPhotosScreen extends StatefulWidget {
  const SimilarPhotosScreen({
    super.key,
    required this.controller,
    required this.keepSide,
  });

  /// The sort screen's controller, so what's decided here counts there.
  final SortController controller;

  /// Which way Keep points, for the zoomed view's buttons.
  final KeepSide keepSide;

  @override
  State<SimilarPhotosScreen> createState() => _SimilarPhotosScreenState();
}

class _SimilarPhotosScreenState extends State<SimilarPhotosScreen> {
  late final _search = SimilarController(
    repository: _sort.repository,
    store: _sort.store,
    // Only photos with no decision: ones already sorted are never offered.
    photos: _sort.unsortedPhotos,
  )..scan();

  SortController get _sort => widget.controller;

  // Which group is showing, and which of its photos are picked to keep.
  // Null means the suggestion, until the user changes it.
  int _at = 0;
  Set<String>? _keep;
  bool _saving = false;

  // What has been decided from this screen, for the closing message.
  int _kept = 0;
  int _marked = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Set<String> _chosen(SimilarGroup group) =>
      _keep ?? {group.photos[group.suggested].id};

  void _toggle(SimilarGroup group, Photo photo) {
    final chosen = {..._chosen(group)};
    if (!chosen.remove(photo.id)) chosen.add(photo.id);
    setState(() => _keep = chosen);
  }

  void _next() => setState(() {
    _at++;
    _keep = null;
  });

  Future<void> _confirm(SimilarGroup group) async {
    final chosen = _chosen(group);
    setState(() => _saving = true);
    try {
      await _sort.decideMany({
        for (final photo in group.photos)
          photo.id: chosen.contains(photo.id) ? Decision.keep : Decision.delete,
      });
      _kept += chosen.length;
      _marked += group.photos.length - chosen.length;
      _next();
    } catch (error) {
      _tell("Couldn't save that. Please try again.\n$error");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // A closer look at one photo. Keep or Delete there picks it for that
  // choice, and brings the user back to the group.
  Future<void> _zoom(
    SimilarGroup group,
    Photo photo,
    ImageProvider preview,
  ) async {
    final decision = await Navigator.of(context).push<Decision>(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          repository: _sort.repository,
          photo: photo,
          preview: preview,
          heroTag: _tag(photo),
          keepSide: widget.keepSide,
        ),
      ),
    );
    if (decision == null || !mounted) return;
    final chosen = {..._chosen(group)};
    if (decision == Decision.keep) {
      chosen.add(photo.id);
    } else {
      chosen.remove(photo.id);
    }
    setState(() => _keep = chosen);
  }

  static Object _tag(Photo photo) => 'similar-${photo.id}';

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) {
        final groups = _search.groups;
        final group = !_search.isScanning && _at < groups.length
            ? groups[_at]
            : null;
        return Scaffold(
          appBar: AppBar(title: const Text('Similar photos')),
          body: _buildBody(context, groups, group),
          bottomNavigationBar: group == null ? null : _buildBar(group),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<SimilarGroup> groups,
    SimilarGroup? group,
  ) {
    final theme = Theme.of(context);
    if (_search.isScanning) {
      return _Scanning(looked: _search.looked, total: _search.toLookAt);
    }
    if (_search.error case final error?) {
      return MessageView('Could not look for similar photos.\n$error');
    }
    if (groups.isEmpty) {
      return const MessageView(
        'No similar photos found. Photos show up here when they look the '
        'same and were taken within ten minutes of each other, such as '
        'several shots of one thing.',
      );
    }
    if (group == null) {
      return _Finished(kept: _kept, marked: _marked);
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 600 ? 3 : 2;
    final tileWidth = (width / columns * MediaQuery.devicePixelRatioOf(context))
        .round();
    final chosen = _chosen(group);
    final span = group.photos.last.date.difference(group.photos.first.date);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Glass(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Group ${_at + 1} of ${groups.length}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.photos.length} shots, taken within '
                    '${formatSpan(span)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a photo to choose which to keep. Press and hold '
                    'to look closer.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: group.photos.length,
            itemBuilder: (context, index) {
              final photo = group.photos[index];
              final image = _sort.repository.imageFor(photo, width: tileWidth);
              return _Tile(
                // A new set of tiles for each group.
                key: ValueKey('$_at/${photo.id}'),
                photo: photo,
                image: image,
                heroTag: _tag(photo),
                keeping: chosen.contains(photo.id),
                suggested: index == group.suggested,
                onTap: () => _toggle(group, photo),
                onZoom: () => _zoom(group, photo, image),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBar(SimilarGroup group) {
    final keeping = _chosen(group).length;
    final marking = group.photos.length - keeping;
    return GlassBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            // Nothing is decided until at least one photo is kept, so a
            // group can never be marked for deletion all at once.
            onPressed: keeping == 0 || _saving ? null : () => _confirm(group),
            icon: const Icon(Icons.check),
            label: Text(
              keeping == 0
                  ? 'Pick at least one to keep'
                  : marking == 0
                  ? 'Keep all $keeping'
                  : 'Keep $keeping, mark $marking to delete',
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _saving ? null : _next,
            child: const Text('Skip this group'),
          ),
        ],
      ),
    );
  }
}

/// A photo in a group: picked to keep (a green edge and tick) or not (dimmed,
/// with a cross). Read out as the file name and which of the two it is.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.photo,
    required this.image,
    required this.heroTag,
    required this.keeping,
    required this.suggested,
    required this.onTap,
    required this.onZoom,
  });

  final Photo photo;
  final ImageProvider image;
  final Object heroTag;
  final bool keeping;

  /// The sharpest of the group, which was picked to start with.
  final bool suggested;
  final VoidCallback onTap;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SortColors.of(context);
    final accent = keeping ? colors.keep : colors.delete;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Semantics(
      label:
          '${photo.name}, ${keeping ? 'keeping' : 'marked to delete'}'
          '${suggested ? ', suggested' : ''}',
      button: true,
      onTap: onTap,
      onLongPress: onZoom,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onZoom,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: keeping ? colors.keep : Colors.transparent,
              width: 3,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: colors.photoMatte,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              // Photos not being kept are dimmed, so the choice reads at a
              // glance.
              if (!keeping)
                ColoredBox(
                  color: theme.colorScheme.surface.withValues(alpha: 0.55),
                ),
              Positioned(
                top: 8,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      keeping ? Icons.check : Icons.close,
                      size: 16,
                      color: onAccent,
                    ),
                  ),
                ),
              ),
              if (suggested)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(
                        'Sharpest',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({required this.looked, required this.total});

  final int looked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A bar once the number to look at is known; spinning until.
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: total == 0 ? null : looked / total,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              total == 0
                  ? 'Getting ready…'
                  : 'Looking at ${formatCount(looked)} of '
                        '${formatCount(total)} photos…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: AppTheme.tabularFigures,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Only photos taken close together in time are compared. What it '
              'learns is remembered, so the next time is quicker.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.kept, required this.marked});

  final int kept;
  final int marked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable, so it still fits on a small phone with large text.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('All groups done', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              marked == 0 && kept == 0
                  ? 'You skipped them all, so nothing was decided.'
                  : 'Kept ${photoCount(kept)} and marked ${photoCount(marked)} '
                        'to delete. Nothing is deleted until you review them. '
                        'Undo on the sorting screen takes back the last group.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to sorting'),
            ),
          ],
        ),
      ),
    );
  }
}
