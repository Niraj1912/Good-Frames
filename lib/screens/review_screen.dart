import 'package:flutter/material.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/models/target_folder.dart';
import 'package:good_frames/state/sort_controller.dart';
import 'package:good_frames/theme/app_theme.dart';
import 'package:good_frames/theme/glass.dart';
import 'package:good_frames/widgets/formatting.dart';
import 'package:good_frames/widgets/message_view.dart';
import 'package:good_frames/widgets/grease_mark.dart';
import 'package:good_frames/widgets/note_card.dart';

/// The last stop before anything is deleted or moved: a grid of every photo
/// marked Delete, and one of every photo swiped down into a folder. Tapping
/// one rescues it (keeps it, or leaves it where it is); the buttons move the
/// rest to the trash, or into their folders, in one go.
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
  // The photos swiped down when the screen opened. Ones left out stay on
  // screen, dimmed, so a wrong tap can be fixed with another tap.
  late final List<({Photo photo, String folder})> _filed =
      _controller.filedPhotos;
  bool _working = false;
  bool _moving = false;
  // How far preparing a big batch has got, shown on the button.
  (int done, int total)? _progress;

  SortController get _controller => widget.controller;

  List<Photo> get _toDelete => [
    for (final photo in _photos)
      if (_controller.decisionFor(photo) == Decision.delete) photo,
  ];

  List<({Photo photo, String folder})> get _toMove => [
    for (final entry in _filed)
      if (_controller.folderFor(entry.photo) != null) entry,
  ];

  // Tap a photo in the move grid: leave it where it is, or queue it again
  // for the folder it was swiped into.
  Future<void> _toggleFiled(({Photo photo, String folder}) entry) async {
    try {
      if (_controller.folderFor(entry.photo) != null) {
        await _controller.unfile(entry.photo);
      } else {
        await _controller.refile(entry.photo, entry.folder);
      }
    } catch (error) {
      _tell("Couldn't save that. Please try again.\n$error");
    }
  }

  Future<void> _moveToFolders() async {
    final count = _toMove.length;
    setState(() => _moving = true);
    final MoveResult result;
    try {
      result = await _controller.moveFiled();
    } catch (error) {
      if (mounted) setState(() => _moving = false);
      _tell("Couldn't move the photos.\n$error");
      return;
    }
    if (!mounted) return;
    setState(() => _moving = false);

    final where = result.folders.length == 1
        ? folderLabel(result.folders.single)
        : '${result.folders.length} folders';
    if (result.cancelled) {
      _tell('Nothing was moved.');
    } else if (result.failed > 0) {
      _tell(
        'Moved ${result.moved} of ${result.requested} into $where. '
        "${result.failed} couldn't be moved; a photo with the same name may "
        'already be there.',
      );
    } else {
      _tell('Moved ${photoCount(count)} into $where.');
      if (_toDelete.isEmpty) Navigator.pop(context);
    }
  }

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
      if (_toMove.isEmpty) Navigator.pop(context);
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
                4 *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final count = _toDelete.length;
        final moveCount = _toMove.length;
        final folderNames = {
          for (final entry in _toMove) folderLabel(entry.folder),
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Review')),
          // The explanation scrolls together with the grid, so with large
          // text it can never squeeze the grid out of the screen.
          body: _photos.isEmpty && _filed.isEmpty
              ? const MessageView('Nothing left to review.')
              : CustomScrollView(
                  slivers: [
                    if (_photos.isNotEmpty) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: NoteCard(
                            icon: Icons.delete_sweep_outlined,
                            colour: SortColors.of(context).delete,
                            text:
                                'Tap a photo to keep it instead. Nothing is '
                                'deleted until you press the button below.\n'
                                '${_controller.repository.trashExplanation}',
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.75,
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
                    if (_filed.isNotEmpty) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: NoteCard(
                            icon: Icons.folder_outlined,
                            colour: const Color(0xFF38BDF8),
                            text:
                                'Swiped down. Tap a photo to leave it where it '
                                'is instead. Nothing moves until you press the '
                                'button below, and Android will ask first.',
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.75,
                              ),
                          itemCount: _filed.length,
                          itemBuilder: (context, index) {
                            final entry = _filed[index];
                            return _FileTile(
                              key: ValueKey('file-${entry.photo.id}'),
                              photo: entry.photo,
                              folder: entry.folder,
                              image: _controller.repository.imageFor(
                                entry.photo,
                                width: tileWidth,
                              ),
                              queued:
                                  _controller.folderFor(entry.photo) != null,
                              onTap: () => _toggleFiled(entry),
                            );
                          },
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
          bottomNavigationBar: GlassBar(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_progress case (final done, final total)) ...[
                  LinearProgressIndicator(value: done / total),
                  const SizedBox(height: 12),
                ],
                if (_filed.isNotEmpty) ...[
                  FilledButton.icon(
                    onPressed: moveCount == 0 || _moving || _working
                        ? null
                        : _moveToFolders,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    icon: const Icon(Icons.drive_file_move_outlined),
                    label: Text(
                      _moving
                          ? 'Waiting for confirmation…'
                          : moveCount == 0
                          ? 'Nothing to move'
                          : 'Move ${photoCount(moveCount)} into '
                                '${folderNames.length == 1 ? folderNames.single : '${folderNames.length} folders'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_photos.isNotEmpty) const SizedBox(height: 8),
                ],
                if (_photos.isNotEmpty)
                  FilledButton.icon(
                    onPressed: count == 0 || _working || _moving
                        ? null
                        : _moveToTrash,
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
        );
      },
    );
  }
}

/// A photo waiting to be moved into a folder. Queued ones have a blue edge
/// and the folder's name; one left out fades back.
class _FileTile extends StatelessWidget {
  const _FileTile({
    super.key,
    required this.photo,
    required this.folder,
    required this.image,
    required this.queued,
    required this.onTap,
  });

  final Photo photo;
  final String folder;
  final ImageProvider image;
  final bool queued;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const blue = Color(0xFF38BDF8);
    return Semantics(
      button: true,
      label:
          '${photo.name}, ${queued ? 'will be moved into ${folderLabel(folder)}' : 'will stay where it is'}',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
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
              if (!queued)
                ColoredBox(color: colors.surface.withValues(alpha: 0.55)),
              if (queued)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: blue, width: 2.5),
                  ),
                ),
              Positioned(
                left: 4,
                bottom: 4,
                child: Icon(
                  queued ? Icons.folder : Icons.folder_off_outlined,
                  size: 18,
                  color: queued ? blue : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sort = SortColors.of(context);
    // Screen readers announce what tapping will do, not just "image".
    return Semantics(
      button: true,
      label: '${photo.name}, ${rescued ? 'will be kept' : 'will be deleted'}',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
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
              // A photo to be deleted fades back and is crossed out, as it
              // would be on a contact sheet. A rescued one is circled, with
              // an edge in the keep colour, so it stands out from the rest.
              if (!rescued)
                ColoredBox(color: colors.surface.withValues(alpha: 0.55)),
              Padding(
                padding: const EdgeInsets.all(5),
                child: GreaseMark(
                  decision: rescued ? Decision.keep : Decision.delete,
                  colour: rescued ? sort.keep : sort.delete,
                  strokeWidth: 3,
                ),
              ),
              if (rescued)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: sort.keep, width: 2.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
