import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/trashed_photo.dart';
import 'package:photo_swipe/state/trash_controller.dart';
import 'package:photo_swipe/theme/app_theme.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';
import 'package:photo_swipe/widgets/skeleton.dart';
import 'package:photo_swipe/widgets/note_card.dart';

/// Photos Good Frames moved to the trash. Pick some and bring them back, or
/// erase them for good. Erasing is the one thing in the app that can't be
/// undone, so it always asks first (and on Android, Android asks too).
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  late final _controller = TrashController(
    repository: widget.repository,
    store: widget.store,
  )..load();

  // Which photos are ticked. Only this screen cares, so it lives here rather
  // than in the controller.
  final _selected = <String>{};
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(TrashedPhoto photo) {
    setState(() {
      if (!_selected.remove(photo.photoId)) _selected.add(photo.photoId);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _controller.photos.length) {
        _selected.clear();
      } else {
        _selected.addAll(_controller.photos.map((photo) => photo.photoId));
      }
    });
  }

  Future<void> _restore() => _act(
    _controller.restore,
    report: (done, chosen) {
      if (done == 0) return 'Nothing was restored.';
      if (done < chosen) {
        return 'Restored $done of $chosen. The rest may already be gone from '
            'the trash.';
      }
      return 'Restored ${photoCount(done)}.';
    },
    failure: "Couldn't restore them.",
  );

  Future<void> _deleteForever() async {
    if (!await _confirmDeleteForever(_selected.length)) return;
    await _act(
      _controller.deleteForever,
      report: (done, chosen) {
        if (done == 0) return 'Nothing was deleted.';
        if (done < chosen) {
          return 'Deleted $done of $chosen forever. The rest are still in the '
              'trash.';
        }
        return 'Deleted ${photoCount(done)} forever.';
      },
      failure: "Couldn't delete them.",
    );
  }

  // The app's own warning, in plain words, before anything is erased. The
  // safe choice is the quiet one; the destructive one is red and named for
  // exactly what it does.
  Future<bool> _confirmDeleteForever(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text('Delete ${photoCount(count)} forever?'),
          content: Text(
            "${count == 1 ? 'It' : 'They'} will be erased for good. Nothing, "
            "including Good Frames, can bring ${count == 1 ? 'it' : 'them'} "
            'back.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  // Runs [action] on the ticked photos, then says how it went.
  Future<void> _act(
    Future<int> Function(List<TrashedPhoto>) action, {
    required String Function(int done, int chosen) report,
    required String failure,
  }) async {
    final chosen = [
      for (final photo in _controller.photos)
        if (_selected.contains(photo.photoId)) photo,
    ];
    setState(() => _working = true);
    try {
      final done = await action(chosen);
      final stillThere = {for (final p in _controller.photos) p.photoId};
      _selected.retainAll(stillThere);
      _tell(report(done, chosen.length));
    } catch (error) {
      _tell('$failure\n$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    // Replace any message still showing, rather than queueing behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final photos = _controller.photos;
        final allSelected =
            photos.isNotEmpty && _selected.length == photos.length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Recently deleted'),
            actions: [
              TextButton(
                onPressed: photos.isEmpty ? null : _toggleAll,
                child: Text(allSelected ? 'Select none' : 'Select all'),
              ),
            ],
          ),
          body: _buildBody(context, photos),
          bottomNavigationBar: _buildActions(context),
        );
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);
    final delete = SortColors.of(context).delete;
    final enabled = _selected.isNotEmpty && !_working;
    return GlassBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selected.isEmpty
                ? 'Tap photos to choose them'
                : '${photoCount(_selected.length)} chosen',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: AppTheme.tabularFigures,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Same red tint as Delete on the sort screen, and on the
              // left, where deleting always is in this app.
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? _deleteForever : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Color.alphaBlend(
                      delete.withValues(alpha: 0.16),
                      theme.colorScheme.surface,
                    ),
                    foregroundColor: delete,
                  ),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete forever'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? _restore : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TrashedPhoto> photos) {
    if (_controller.isLoading) {
      return const PhotoGridSkeleton();
    }
    if (_controller.loadError case final error?) {
      return MessageView('Could not load the trash.\n$error');
    }
    if (photos.isEmpty) {
      return const MessageView(
        'Nothing here. Photos you move to the trash with Good Frames show up '
        'here, so you can bring them back.',
      );
    }

    final tileWidth =
        (MediaQuery.sizeOf(context).width /
                3 *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    // The explanation scrolls with the grid, so large text never squeezes
    // the grid off the screen.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverToBoxAdapter(
            child: NoteCard(
              icon: Icons.restore_from_trash_outlined,
              colour: Theme.of(context).colorScheme.primary,
              text:
                  'Choose photos to bring back, or to delete for good.\n'
                  '${widget.repository.trashExplanation}',
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return _TrashTile(
                key: ValueKey(photo.photoId),
                photo: photo,
                width: tileWidth,
                timeLeft: _controller.timeLeft(photo),
                selected: _selected.contains(photo.photoId),
                onTap: () => _toggle(photo),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    super.key,
    required this.photo,
    required this.width,
    required this.timeLeft,
    required this.selected,
    required this.onTap,
  });

  final TrashedPhoto photo;
  final int width;
  final Duration? timeLeft;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: const Icon(Icons.image_outlined),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: photo.name,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo.thumbnailPath case final path?)
                Image(
                  image: ResizeImage(FileImage(File(path)), width: width),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                )
              else
                placeholder,
              if (timeLeft case final left?)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        _daysLeft(left),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.primary, width: 4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.check_circle, color: colors.primary),
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

String _daysLeft(Duration left) {
  final days = left.inDays;
  if (days < 1) return 'Less than a day left';
  return days == 1 ? '1 day left' : '$days days left';
}
