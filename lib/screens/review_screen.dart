import 'package:flutter/material.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/state/sort_controller.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// The last stop before anything is deleted: a grid of every photo marked
/// Delete. Tapping one rescues it; the button moves the rest to the trash in
/// one go.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.controller});

  /// The same controller as the sort screen, so both always agree.
  final SortController controller;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // The photos marked when the screen opened. Rescued ones stay on screen,
  // dimmed, so a wrong tap can be fixed with another tap.
  late List<Photo> _photos = _controller.markedForDelete;
  bool _working = false;
  // How far preparing a big batch has got, shown on the button.
  (int done, int total)? _progress;

  SortController get _controller => widget.controller;

  List<Photo> get _toDelete => [
    for (final photo in _photos)
      if (_controller.decisionFor(photo) == Decision.delete) photo,
  ];

  Future<void> _toggle(Photo photo) async {
    final next = _controller.decisionFor(photo) == Decision.delete
        ? Decision.keep
        : Decision.delete;
    try {
      await _controller.changeDecision(photo, next);
    } catch (error) {
      _tell("Couldn't save that. Please try again.\n$error");
    }
  }

  Future<void> _moveToTrash() async {
    final count = _toDelete.length;
    final repository = _controller.repository;

    // Android asks the user itself. Elsewhere, the app must ask.
    if (!repository.confirmsTrashItself) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Move ${photoCount(count)} to the trash?'),
          content: Text(repository.trashExplanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            // Red, not the accent: this is the destructive choice.
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Move to trash'),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }

    setState(() => _working = true);
    final TrashResult result;
    try {
      result = await _controller.trashMarked(
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _progress = null;
        });
      }
      _tell("Couldn't move the photos to the trash.\n$error");
      return;
    }
    if (!mounted) return;

    setState(() {
      _working = false;
      _progress = null;
      // Moved photos have no decision any more; drop them from the grid.
      _photos = [
        for (final photo in _photos)
          if (_controller.decisionFor(photo) != null) photo,
      ];
    });

    final alreadyGone = result.vanished > 0
        ? ' ${photoCount(result.vanished)} had already been deleted '
              'elsewhere.'
        : '';
    if (result.cancelled) {
      _tell('Nothing was deleted.');
    } else if (result.failed > 0) {
      _tell(
        'Moved ${result.moved} of ${result.requested}. ${result.failed} '
        'couldn\'t be moved; they may be open in another app.$alreadyGone',
      );
    } else {
      final freed = result.freedBytes > 0
          ? ' ${formatSize(result.freedBytes)} freed.'
          : '';
      _tell(
        'Moved ${photoCount(result.moved)} to the trash.$freed$alreadyGone',
      );
      Navigator.pop(context);
    }
  }

  // The messenger belongs to the whole app, so a message shown just before
  // leaving this screen stays visible on the next one. Any message still
  // showing is replaced, not queued behind.
  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tileWidth =
        (MediaQuery.sizeOf(context).width /
                3 *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final count = _toDelete.length;
        return Scaffold(
          appBar: AppBar(title: const Text('Review')),
          // The explanation scrolls together with the grid, so with large
          // text it can never squeeze the grid out of the screen.
          body: _photos.isEmpty
              ? const MessageView('Nothing left to review.')
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Tap a photo to keep it instead. Nothing is deleted '
                          'until you press the button below.\n'
                          '${_controller.repository.trashExplanation}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: _photos.length,
                        itemBuilder: (context, index) {
                          final photo = _photos[index];
                          return _ReviewTile(
                            key: ValueKey(photo.id),
                            photo: photo,
                            image: _controller.repository.imageFor(
                              photo,
                              width: tileWidth,
                            ),
                            rescued:
                                _controller.decisionFor(photo) !=
                                Decision.delete,
                            onTap: () => _toggle(photo),
                          );
                        },
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_progress case (final done, final total)) ...[
                    LinearProgressIndicator(value: done / total),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: count == 0 || _working ? null : _moveToTrash,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(switch (_progress) {
                      (final done, final total) when done < total =>
                        'Preparing $done of $total…',
                      (_, _) => 'Waiting for confirmation…',
                      null when count == 0 => 'Nothing to delete',
                      null => 'Move ${photoCount(count)} to the trash',
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    super.key,
    required this.photo,
    required this.image,
    required this.rescued,
    required this.onTap,
  });

  final Photo photo;
  final ImageProvider image;
  final bool rescued;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Screen readers announce what tapping will do, not just "image".
    return Semantics(
      button: true,
      label: '${photo.name}, ${rescued ? 'will be kept' : 'will be deleted'}',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
              if (rescued)
                const ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite, color: Colors.white),
                        Text('Keep', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                )
              else
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colors.error,
                    child: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: colors.onError,
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
