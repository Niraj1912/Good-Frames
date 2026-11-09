import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/data/photo_repository.dart';
import 'package:good_frames/models/album.dart';
import 'package:good_frames/models/decision.dart';
import 'package:good_frames/models/keep_side.dart';
import 'package:good_frames/models/photo.dart';
import 'package:good_frames/screens/photo_viewer_screen.dart';
import 'package:good_frames/screens/review_screen.dart';
import 'package:good_frames/state/settings.dart';
import 'package:good_frames/state/sort_controller.dart';
import 'package:good_frames/theme/app_theme.dart';
import 'package:good_frames/theme/glass.dart';
import 'package:good_frames/models/target_folder.dart';
import 'package:good_frames/widgets/folder_picker.dart';
import 'package:good_frames/widgets/formatting.dart';
import 'package:good_frames/widgets/message_view.dart';
import 'package:good_frames/widgets/skeleton.dart';
import 'package:good_frames/widgets/month_picker.dart';
import 'package:good_frames/widgets/photo_card.dart';
import 'package:good_frames/widgets/share_photo.dart';

import 'package:good_frames/widgets/swipe_card.dart';
import 'package:good_frames/widgets/swipe_hint.dart';

/// Shows an album's photos one at a time so the user can mark each one to
/// keep or delete. Decisions are only recorded here; nothing is deleted.
class SortScreen extends StatefulWidget {
  const SortScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.album,
    required this.settings,
  });

  final PhotoRepository repository;
  final DecisionStore store;
  final Album album;
  final Settings settings;

  @override
  State<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends State<SortScreen> {
  late final _controller = SortController(
    repository: widget.repository,
    store: widget.store,
    album: widget.album,
    order: widget.settings.order,
  )..load();

  // Lets the buttons and keys swipe the card, so they animate like a drag.
  final _cardKey = GlobalKey<SwipeCardState>();
  final _dragProgress = ValueNotifier(0.0);
  final _upProgress = ValueNotifier(0.0);
  final _downProgress = ValueNotifier(0.0);
  // After an undo, the side the photo comes back from: the side it left on.
  SwipeDirection? _enterFrom;

  @override
  void dispose() {
    _controller.dispose();
    _dragProgress.dispose();
    _upProgress.dispose();
    _downProgress.dispose();
    super.dispose();
  }

  KeepSide get _keepSide => widget.settings.keepSide;

  // Swipes keep one way and delete the other: right keeps, unless the user
  // swapped them in Settings.
  SwipeDirection _directionFor(Decision decision) =>
      (decision == Decision.keep) == (_keepSide == KeepSide.right)
      ? SwipeDirection.right
      : SwipeDirection.left;

  // For left and right only: up isn't a decision.
  Decision _decisionFor(SwipeDirection direction) =>
      direction == _directionFor(Decision.keep)
      ? Decision.keep
      : Decision.delete;

  void _swipe(SwipeDirection direction) =>
      _cardKey.currentState?.swipe(direction);
  void _later() => _swipe(SwipeDirection.up);

  // Swiping down files the photo into the chosen folder, where that's
  // possible.
  bool get _canFile => widget.repository.canMoveToFolders;
  void _fileDown() {
    if (_canFile) _swipe(SwipeDirection.down);
  }

  Future<String?> _chooseFolder() =>
      showFolderPicker(context, widget.settings, widget.repository);

  void _undo() {
    _enterFrom = _controller.lastWasPutOff
        ? SwipeDirection.up
        : _controller.lastWasFiled
        ? SwipeDirection.down
        : switch (_controller.lastDecision) {
            final decision? => _directionFor(decision),
            null => null,
          };
    _run(_controller.undo);
  }

  // Opens the photo full screen to zoom in. A decision made there swipes
  // the card away once the viewer has closed, just like a drag would.
  Future<void> _openViewer(Photo photo, ImageProvider preview) async {
    final decision = await Navigator.of(context).push<Decision>(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          repository: widget.repository,
          photo: photo,
          preview: preview,
          heroTag: _heroTag(photo),
          keepSide: _keepSide,
        ),
      ),
    );
    if (!mounted || decision == null) return;
    _swipe(_directionFor(decision));
  }

  // The word on the stamp while dragging down: the folder's name, short.
  static String _stampLabel(String? folder) {
    if (folder == null) return 'FILE';
    final name = folderLabel(folder).toUpperCase();
    return name.length > 14 ? '${name.substring(0, 13)}…' : name;
  }

  static Object _heroTag(Photo photo) => 'photo-${photo.id}';

  Future<void> _onSwiped(SwipeDirection direction) async {
    _enterFrom = null; // The next photo just appears behind.
    if (direction == SwipeDirection.down) {
      // The first time, there's no folder yet: ask, and if the user closes
      // the sheet, the photo simply comes back.
      var folder = widget.settings.targetFolder;
      folder ??= await _chooseFolder();
      if (folder == null || !mounted) {
        _cardKey.currentState?.comeBack();
        return;
      }
      final chosen = folder;
      final saved = await _run(
        () => _controller.decide(Decision.keep, folder: chosen),
      );
      if (!saved) _cardKey.currentState?.comeBack();
      return;
    }
    if (direction == SwipeDirection.up) {
      // With nothing else left to sort, the same photo is next again, so
      // bring the card straight back.
      final onlyOneLeft =
          _controller.isFullyLoaded && _controller.upcoming(1).isEmpty;
      _controller.putOff();
      if (onlyOneLeft) _cardKey.currentState?.comeBack();
      return;
    }
    final saved = await _run(() => _controller.decide(_decisionFor(direction)));
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

  Future<void> _pickMonth() async {
    final before = _controller.month;
    await showMonthPicker(context, _controller);
    if (_controller.month != before) _enterFrom = null;
  }

  void _showMonth(DateTime? month) {
    _enterFrom = null;
    _controller.showMonth(month);
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
          'This forgets your decisions for the '
          '${formatCount(_controller.total)} photos '
          '${switch (_controller.month) {
            final month? => 'from ${formatMonth(month)} in',
            null => 'in',
          }} ${widget.album.name}. No photos are deleted.',
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
        // Left-aligned: the title and three actions don't both fit around
        // the middle of a narrow phone.
        centerTitle: false,
        // Taller with large text, so the month under the name still fits.
        toolbarHeight: MediaQuery.textScalerOf(context)
            .scale(kToolbarHeight)
            .clamp(kToolbarHeight, 2 * kToolbarHeight),
        title: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => SortTitle(
            albumName: widget.album.name,
            month: _controller.month,
            onPickMonth: _controller.months.length > 1 ? _pickMonth : null,
          ),
        ),
        actions: [
          // Review what's marked so far, without sorting the whole album.
          // Both buttons wait until every page has loaded, so they always
          // act on the whole album.
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final count = _controller.deleteCount + _controller.filedCount;
              final ready = _controller.isFullyLoaded;
              return GlassCapsule(
                children: [
                  // Send the photo on show to someone, then carry on sorting.
                  IconButton(
                    onPressed: _controller.current == null
                        ? null
                        : () => sharePhoto(
                            context,
                            widget.repository,
                            _controller.current!,
                          ),
                    icon: const Icon(Icons.share),
                    tooltip: 'Share photo',
                  ),
                  IconButton(
                    onPressed: count > 0 && ready ? _openReview : null,
                    icon: Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(Icons.delete_sweep_outlined),
                    ),
                    tooltip: _controller.filedCount > 0
                        ? 'Review photos to delete or move'
                        : 'Review photos to delete',
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
          const SizedBox(width: 12),
        ],
      ),
      // Keyboard shortcuts for the Windows build. The arrows swipe that way,
      // so they follow the swipe directions. They do nothing once the album
      // is done, but Undo still works there.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _swipe(SwipeDirection.left),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _swipe(SwipeDirection.right),
          const SingleActivator(LogicalKeyboardKey.arrowUp): _later,
          const SingleActivator(LogicalKeyboardKey.arrowDown): _fileDown,
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
      return const SortSkeleton();
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
            null when !controller.isFullyLoaded => const SortSkeleton(),
            null => _DoneView(
              kept: controller.keepCount,
              deleted: controller.deleteCount,
              filed: controller.filedCount,
              month: controller.month,
              nextMonth: controller.nextMonth,
              onShowMonth: _showMonth,
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
    final image = widget.repository.imageFor(photo, width: width);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The next photo waits behind, out of sight until the top
                // card is dragged: then it fades in and grows to full size,
                // ready to take its place. Hidden at rest, so a bigger photo
                // never shows round the edges of a smaller one.
                if (upcoming.isNotEmpty)
                  ListenableBuilder(
                    listenable: Listenable.merge([_dragProgress, _upProgress]),
                    builder: (context, child) {
                      final shown = math.max(
                        _dragProgress.value.abs(),
                        _upProgress.value,
                      );
                      return Opacity(
                        opacity: shown,
                        child: Transform.scale(
                          scale: 0.94 + 0.06 * shown,
                          child: child,
                        ),
                      );
                    },
                    // Still built while hidden, so its photo is decoded and
                    // ready the moment it comes to the front.
                    child: Center(
                      child: PhotoCard(
                        image: widget.repository.imageFor(
                          upcoming.first,
                          width: width,
                        ),
                      ),
                    ),
                  ),
                SwipeCard(
                  key: _cardKey,
                  cardId: photo.id,
                  dragProgress: _dragProgress,
                  upProgress: _upProgress,
                  downProgress: _downProgress,
                  canSwipeDown: _canFile,
                  downLabel: _stampLabel(widget.settings.targetFolder),
                  enterFrom: _enterFrom,
                  keepSide: _keepSide,
                  vibration: widget.settings.vibration,
                  onSwiped: _onSwiped,
                  onTap: () => _openViewer(photo, image),
                  // Sized by the photo, so the zoom hint sits on its corner.
                  // The file name isn't shown, but screen readers get it.
                  child: Semantics(
                    label: photo.name,
                    image: true,
                    child: Stack(
                      children: [
                        PhotoCard(image: image, heroTag: _heroTag(photo)),
                        // Says "you can zoom"; the tap itself is handled by
                        // the whole card, so this just shows the way.
                        const Positioned(
                          right: 12,
                          bottom: 12,
                          child: IgnorePointer(child: _ZoomHint()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Just the counts, so the controls sit right under the photo.
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _ProgressLine(controller: _controller),
        ),
        // Undo and the swipe hint, on one slim pane of glass.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Glass(
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SwipeHint(
                  keepSide: _keepSide,
                  onUndo: _controller.canUndo ? _undo : null,
                  onLeft: () => _swipe(SwipeDirection.left),
                  onUp: _later,
                  onRight: () => _swipe(SwipeDirection.right),
                  dragProgress: _dragProgress,
                  upProgress: _upProgress,
                  onDown: _canFile ? _fileDown : null,
                  downProgress: _downProgress,
                ),
                if (_canFile)
                  _FolderChip(settings: widget.settings, onTap: _chooseFolder),
                if (isDesktop) ...[
                  const SizedBox(height: 8),
                  Text(
                    switch (_keepSide) {
                      KeepSide.right =>
                        '←  Delete    ↑  Later    →  Keep    '
                            'Z  Undo    Click to zoom',
                      KeepSide.left =>
                        '←  Keep    ↑  Later    →  Delete    '
                            'Z  Undo    Click to zoom',
                    },
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Down → Trip to Goa": which folder a swipe down files into. Tapping it
/// chooses another.
class _FolderChip extends StatelessWidget {
  const _FolderChip({required this.settings, required this.onTap});

  final Settings settings;
  final Future<String?> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final folder = settings.targetFolder;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            button: true,
            label: folder == null
                ? 'Choose a folder for swipes down'
                : 'Swipes down go to ${folderLabel(folder)}. Change folder',
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        folder == null
                            ? 'Choose a folder for swipes down'
                            : 'Down → ${folderLabel(folder)}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "2 / 40 sorted" with the kept and deleted counts beside it: a single quiet
/// line in place of a panel, so the buttons stay close to the photo.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.controller});

  final SortController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = SortColors.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: AppTheme.tabularFigures,
    );

    Widget tally(String label, int count, IconData icon, Color colour) =>
        Semantics(
          label: '$label ${formatCount(count)}',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: 3),
              Text(formatCount(count), style: quiet),
            ],
          ),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 2,
      children: [
        Text(
          '${formatCount(controller.sortedCount)} / '
          '${formatCount(controller.total)} sorted',
          style: quiet,
        ),
        tally('Keep', controller.keepCount, Icons.check, colours.keep),
        tally('Delete', controller.deleteCount, Icons.close, colours.delete),
        if (controller.laterCount > 0)
          tally(
            'Later',
            controller.laterCount,
            Icons.schedule,
            theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

/// A small magnifier in the card's corner, showing the photo can be opened:
/// a bead of dark glass, so it stays clear on any photo. Tinted, not
/// blurred: it moves with every drag, and a blur would be redrawn each
/// frame.
class _ZoomHint extends StatelessWidget {
  const _ZoomHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.zoom_in, color: Colors.white, size: 20),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.kept,
    required this.deleted,
    required this.filed,
    required this.month,
    required this.nextMonth,
    required this.onShowMonth,
    required this.onReview,
    required this.onUndo,
  });

  final int kept;
  final int deleted;

  /// How many of the kept photos are waiting to be moved into folders.
  final int filed;

  /// The month just finished, or null for the whole album.
  final DateTime? month;

  /// The next month with photos still to sort, offered as the next step.
  final DateTime? nextMonth;
  final ValueChanged<DateTime?> onShowMonth;
  final VoidCallback onReview;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SortColors.of(context);
    final nextMonth = this.nextMonth;
    // Scrollable, so it still fits on a small phone with large text.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Glass(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (month) {
                    final month? => '${formatMonth(month)} sorted',
                    null => 'All sorted',
                  },
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // IntrinsicHeight, so the two tiles are always the same
                // height, even when large text wraps one of them.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Tally(
                          count: kept,
                          label: 'to keep',
                          icon: Icons.check,
                          colour: colors.keep,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tally(
                          count: deleted,
                          label: 'to delete',
                          icon: Icons.close,
                          colour: colors.delete,
                        ),
                      ),
                    ],
                  ),
                ),
                if (deleted > 0 || filed > 0) ...[
                  const SizedBox(height: 20),
                  Text(
                    filed > 0
                        ? 'Nothing is deleted or moved until you review them.'
                        : 'Nothing is deleted until you review them.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onReview,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(
                        'Review ${[if (deleted > 0) '${formatCount(deleted)} to delete', if (filed > 0) '${formatCount(filed)} to move'].join(', ')}',
                      ),
                    ),
                  ),
                ],
                // One month at a time: straight on to the next one.
                if (nextMonth != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => onShowMonth(nextMonth),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text('Next: ${formatMonth(nextMonth)}'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo last'),
                    ),
                    if (month != null)
                      TextButton.icon(
                        onPressed: () => onShowMonth(null),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('All months'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the two totals at the end: a big number on a soft wash of its
/// meaning colour. Read out as one phrase, such as "12 to keep".
class _Tally extends StatelessWidget {
  const _Tally({
    required this.count,
    required this.label,
    required this.icon,
    required this.colour,
  });

  final int count;
  final String label;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${formatCount(count)} $label',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colour.withValues(alpha: 0.14),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colour),
              const SizedBox(height: 12),
              // Shrinks rather than overflowing for a very big number.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatCount(count),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w700,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
