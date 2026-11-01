import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/screens/review_screen.dart';
import 'package:photo_swipe/state/sort_controller.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/widgets/decision_buttons.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';
import 'package:photo_swipe/widgets/photo_card.dart';
import 'package:photo_swipe/widgets/photo_info.dart';
import 'package:photo_swipe/widgets/sort_progress.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

/// Shows an album's photos one at a time so the user can mark each one to
/// keep or delete. Decisions are only recorded here; nothing is deleted.
class SortScreen extends StatefulWidget {
  const SortScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.album,
  });

  final PhotoRepository repository;
  final DecisionStore store;
  final Album album;

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  late final _controller = SortController(
    repository: widget.repository,
    store: widget.store,
    album: widget.album,
  )..load();

  // Lets the buttons and keys swipe the card, so they animate like a drag.
  final _cardKey = GlobalKey<SwipeCardState>();
  final _dragProgress = ValueNotifier(0.0);
  // After an undo, the side the photo comes back from: the side it left on.
  SwipeDirection? _enterFrom;

  @override
  void dispose() {
    _controller.dispose();
    _dragProgress.dispose();
    super.dispose();
  }

  void _keep() => _cardKey.currentState?.swipe(SwipeDirection.right);
  void _delete() => _cardKey.currentState?.swipe(SwipeDirection.left);

  void _undo() {
    _enterFrom = switch (_controller.lastDecision) {
      Decision.keep => SwipeDirection.right,
      Decision.delete => SwipeDirection.left,
      null => null,
    };
    _run(_controller.undo);
  }

  Future<void> _onSwiped(SwipeDirection direction) async {
    _enterFrom = null; // The next photo just appears behind.
    final decision = direction == SwipeDirection.right
        ? Decision.keep
        : Decision.delete;
    final saved = await _run(() => _controller.decide(decision));
    // The decision was taken back, so bring the card back too.
    if (!saved) _cardKey.currentState?.comeBack();
  }

  // Runs a controller action, tells the user if saving failed, and reports
  // whether it worked.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text("Couldn't save that. Please try again.\n$error"),
            ),
          );
      }
      return false;
    }
  }

  // Starts decoding the photos after the next one, so each card is ready
  // the moment it comes up. Errors are ignored here: a broken photo shows
  // its placeholder when it's reached.
  void _preload(Iterable<Photo> photos, int width) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final photo in photos) {
        precacheImage(
          widget.repository.imageFor(photo, width: width),
          context,
          onError: (_, _) {},
        );
      }
    });
  }

  void _openReview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(controller: _controller),
      ),
    );
  }

  Future<void> _confirmStartOver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over?'),
        content: Text(
          'This forgets your decisions for the ${_controller.total} photos '
          'in ${widget.album.name}. No photos are deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _run(_controller.startOver);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: [
          // Review what's marked so far, without sorting the whole album.
          // Both buttons wait until every page has loaded, so they always
          // act on the whole album.
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final count = _controller.deleteCount;
              final ready = _controller.isFullyLoaded;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: count > 0 && ready ? _openReview : null,
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.delete_sweep_outlined),
                    ),
                    tooltip: 'Review photos to delete',
                  ),
                  IconButton(
                    onPressed: ready ? _confirmStartOver : null,
                    icon: const Icon(Icons.restart_alt),
                    tooltip: 'Start over',
                  ),
                ],
              );
            },
          ),
        ],
      ),
      // Keyboard shortcuts for the Windows build. Delete and Keep do nothing
      // once the album is done, but Undo still works there.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _delete,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _keep,
          const SingleActivator(LogicalKeyboardKey.keyZ): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.backspace): _undo,
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final controller = _controller;
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadError case final error?) {
      return MessageView('Could not load photos.\n$error');
    }
    if (controller.isFullyLoaded && controller.total == 0) {
      return const MessageView('This album is empty.');
    }

    final photo = controller.current;
    return Column(
      children: [
        SortProgress(
          sorted: controller.sortedCount,
          total: controller.total,
          kept: controller.keepCount,
          deleted: controller.deleteCount,
        ),
        if (!controller.isFullyLoaded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Loading ${formatCount(controller.loadedCount)} of '
              '${formatCount(controller.total)} '
              'photos…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: switch (photo) {
            final photo? => _buildPhoto(context, photo),
            // Sorted everything loaded so far; more pages are on the way.
            null when !controller.isFullyLoaded => const Center(
              child: CircularProgressIndicator(),
            ),
            null => _DoneView(
              kept: controller.keepCount,
              deleted: controller.deleteCount,
              onReview: _openReview,
              onUndo: controller.canUndo ? _undo : null,
            ),
          },
        ),
      ],
    );
  }

  Widget _buildPhoto(BuildContext context, Photo photo) {
    // Decode at the screen's real pixel width, not the photo's full size.
    // Every card uses the same width, so an image decoded early for the
    // card behind is found in the cache when it moves to the front.
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final theme = Theme.of(context);
    final isDesktop = switch (theme.platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final upcoming = _controller.upcoming(3);
    _preload(upcoming.skip(1), width);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The next photo waits behind, slightly smaller, and grows
                // as the top card is dragged away.
                if (upcoming.isNotEmpty)
                  ValueListenableBuilder(
                    valueListenable: _dragProgress,
                    builder: (context, progress, child) => Transform.scale(
                      scale: 0.94 + 0.06 * progress.abs(),
                      child: child,
                    ),
                    child: PhotoCard(
                      image: widget.repository.imageFor(
                        upcoming.first,
                        width: width,
                      ),
                    ),
                  ),
                SwipeCard(
                  key: _cardKey,
                  cardId: photo.id,
                  dragProgress: _dragProgress,
                  enterFrom: _enterFrom,
                  onSwiped: _onSwiped,
                  child: PhotoCard(
                    image: widget.repository.imageFor(photo, width: width),
                  ),
                ),
              ],
            ),
          ),
        ),
        PhotoInfo(photo: photo),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              DecisionButtons(
                onDelete: _delete,
                onKeep: _keep,
                onUndo: _controller.canUndo ? _undo : null,
              ),
              if (isDesktop) ...[
                const SizedBox(height: 8),
                Text(
                  '←  Delete      Z  Undo      →  Keep',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.kept,
    required this.deleted,
    required this.onReview,
    required this.onUndo,
  });

  final int kept;
  final int deleted;
  final VoidCallback onReview;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SortColors.of(context);
    final number = TextStyle(
      fontWeight: FontWeight.w700,
      fontFeatures: AppTheme.tabularFigures,
    );
    // Scrollable, so it still fits on a small phone with large text.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('All sorted', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatCount(kept),
                    style: number.copyWith(color: colors.keep),
                  ),
                  const TextSpan(text: ' to keep, '),
                  TextSpan(
                    text: formatCount(deleted),
                    style: number.copyWith(color: colors.delete),
                  ),
                  const TextSpan(text: ' to delete.'),
                ],
              ),
              style: theme.textTheme.bodyLarge,
            ),
            if (deleted > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Nothing is deleted until you review them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text('Review ${formatCount(deleted)} to delete'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo),
              label: const Text('Undo last'),
            ),
          ],
        ),
      ),
    );
  }
}
