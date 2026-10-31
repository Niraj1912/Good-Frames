import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/album.dart';
import 'package:photo_swipe/models/decision.dart';
import 'package:photo_swipe/models/photo.dart';
import 'package:photo_swipe/state/sort_controller.dart';
import 'package:photo_swipe/widgets/decision_buttons.dart';
import 'package:photo_swipe/widgets/message_view.dart';
import 'package:photo_swipe/widgets/photo_frame.dart';
import 'package:photo_swipe/widgets/photo_info.dart';
import 'package:photo_swipe/widgets/sort_progress.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _keep() => _run(() => _controller.decide(Decision.keep));
  void _delete() => _run(() => _controller.decide(Decision.delete));
  void _undo() => _run(_controller.undo);

  // Runs a controller action and tells the user if saving failed.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't save that. Please try again.\n$error"),
        ),
      );
    }
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
          IconButton(
            onPressed: _confirmStartOver,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Start over',
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
    if (controller.total == 0) {
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
        Expanded(
          child: photo == null
              ? _DoneView(
                  kept: controller.keepCount,
                  deleted: controller.deleteCount,
                  onUndo: controller.canUndo ? _undo : null,
                )
              : _buildPhoto(context, photo),
        ),
      ],
    );
  }

  Widget _buildPhoto(BuildContext context, Photo photo) {
    // Decode at the screen's real pixel width, not the photo's full size.
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

    return Column(
      children: [
        Expanded(
          child: PhotoFrame(
            image: widget.repository.imageFor(photo, width: width),
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
    required this.onUndo,
  });

  final int kept;
  final int deleted;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('All sorted!', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('$kept to keep, $deleted to delete.'),
            const SizedBox(height: 4),
            Text(
              'Nothing has been deleted yet.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
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
