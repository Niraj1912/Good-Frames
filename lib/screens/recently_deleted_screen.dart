import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/trashed_photo.dart';
import 'package:photo_swipe/state/trash_controller.dart';
import 'package:photo_swipe/widgets/formatting.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// Photos SwipeSort moved to the trash. Pick some and bring them back.
/// There's deliberately no "delete forever" here: the app never erases.
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

  Future<void> _restore() async {
    final chosen = [
      for (final photo in _controller.photos)
        if (_selected.contains(photo.photoId)) photo,
    ];
    setState(() => _working = true);
    try {
      final restored = await _controller.restore(chosen);
      final stillThere = {for (final p in _controller.photos) p.photoId};
      _selected.retainAll(stillThere);
      if (restored == 0) {
        _tell('Nothing was restored.');
      } else if (restored < chosen.length) {
        _tell(
          'Restored $restored of ${chosen.length}. The rest may already be '
          'gone from the trash.',
        );
      } else {
        _tell('Restored ${photoCount(restored)}.');
      }
    } catch (error) {
      _tell("Couldn't restore them.\n$error");
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
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || _working ? null : _restore,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                icon: const Icon(Icons.restore),
                label: Text(
                  _selected.isEmpty
                      ? 'Choose photos to restore'
                      : 'Restore ${photoCount(_selected.length)}',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<TrashedPhoto> photos) {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.loadError case final error?) {
      return MessageView('Could not load the trash.\n$error');
    }
    if (photos.isEmpty) {
      return const MessageView(
        'Nothing here. Photos you move to the trash with SwipeSort show up '
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
            child: Text(
              'Tap the photos you want back.\n'
              '${widget.repository.trashExplanation}',
              style: Theme.of(context).textTheme.bodyMedium,
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
