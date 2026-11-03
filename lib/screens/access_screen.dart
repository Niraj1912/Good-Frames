import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/chosen_folder.dart';
import 'package:photo_swipe/screens/album_picker_screen.dart';
import 'package:photo_swipe/screens/manage_folders_screen.dart';
import 'package:photo_swipe/screens/settings_screen.dart';
import 'package:photo_swipe/state/settings.dart';

/// The first screen: gets access to photos, then shows the albums.
///
/// Where there's a choice (Android), it first asks what SwipeSort should
/// see: folders the user picks, or every photo. Elsewhere it just asks for
/// access, and explains if the user refuses.
class AccessScreen extends StatefulWidget {
  const AccessScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.settings,
    this.folders,
  });

  /// Every photo: the phone's whole gallery, or the test folder on Windows.
  final PhotoRepository repository;

  /// Only folders the user picks, on Android. Null where there's no such
  /// choice.
  final ChosenFoldersRepository? folders;

  final DecisionStore store;
  final Settings settings;

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

enum _Showing { checking, choice, denied, allPhotos, folders }

class _AccessScreenState extends State<AccessScreen>
    with WidgetsBindingObserver {
  _Showing _showing = _Showing.checking;
  AccessStatus _status = AccessStatus.denied;
  bool _refused = false; // Said no to all photos on the choice screen.
  bool _sentToSettings = false;
  // The folders shared, while showing them.
  List<ChosenFolder> _chosen = [];
  // Where to go back to if the user cancels the choice screen, when they
  // opened it from Settings to switch. Null on first launch: no going back.
  _Showing? _cancelTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the Settings app: check whether the user allowed access there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sentToSettings) {
      _sentToSettings = false;
      _start();
    }
  }

  // Works out what to show, asking the user only when there's no choice to
  // offer first.
  Future<void> _start() async {
    _cancelTo = null; // Starting afresh: what was shown before may be gone.
    final folders = widget.folders;
    if (folders == null) return _askForAllPhotos();
    final chosen = await folders.chosenFolders();
    if (chosen.isNotEmpty) {
      _chosen = chosen;
      return _show(_Showing.folders);
    }
    // Someone who already allowed access goes straight to their albums.
    final status = await widget.repository.checkAccess();
    if (status == AccessStatus.denied) return _show(_Showing.choice);
    _status = status;
    _show(_Showing.allPhotos);
  }

  void _show(_Showing showing) {
    if (!mounted) return;
    setState(() {
      _showing = showing;
      if (showing != _Showing.choice) _cancelTo = null;
    });
  }

  Future<void> _askForAllPhotos() async {
    final status = await widget.repository.requestAccess();
    if (!mounted) return;
    setState(() {
      _status = status;
      if (status != AccessStatus.denied) {
        _showing = _Showing.allPhotos;
        _cancelTo = null;
      } else if (widget.folders == null) {
        _showing = _Showing.denied;
      } else {
        _showing = _Showing.choice;
        _refused = true;
      }
    });
  }

  Future<void> _chooseFolder() async {
    if (await widget.folders!.chooseFolder() != null) {
      _chosen = await widget.folders!.chosenFolders();
      _show(_Showing.folders);
    }
  }

  // From Settings, while seeing all photos: offer the same choice as on
  // first launch, with a way back.
  void _offerChoice() {
    setState(() {
      _cancelTo = _showing;
      _refused = false;
      _showing = _Showing.choice;
    });
  }

  void _cancelChoice() {
    if (_cancelTo case final previous?) _show(previous);
  }

  Future<void> _manageFolders() async {
    final useAllPhotos = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManageFoldersScreen(folders: widget.folders!),
      ),
    );
    if (!mounted) return;
    if (useAllPhotos ?? false) return _askForAllPhotos();
    final chosen = await widget.folders!.chosenFolders();
    // With every folder removed, start again from the choice.
    if (chosen.isEmpty) return _start();
    if (mounted) setState(() => _chosen = chosen);
  }

  Future<void> _openSettings() async {
    _sentToSettings = true;
    await widget.repository.openAccessSettings();
  }

  // What SwipeSort sees, for the Settings screen, and how to change it:
  // the Folders screen for folders, the first-launch choice otherwise.
  PhotoSource? get _photoSource {
    if (widget.folders == null) return null;
    if (_showing == _Showing.folders) {
      return (
        summary: _chosen.length == 1
            ? 'Only the ${_chosen.single.name} folder'
            : 'Only ${_chosen.length} folders',
        change: _manageFolders,
      );
    }
    return (
      summary: _status == AccessStatus.limited
          ? 'Only photos you selected'
          : 'All photos',
      change: _offerChoice,
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_showing) {
      _Showing.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _Showing.denied => _AccessDeniedView(
        onAllow: _askForAllPhotos,
        onOpenSettings: _openSettings,
      ),
      _Showing.choice => _ChoiceView(
        refused: _refused,
        onChooseFolder: _chooseFolder,
        onAllPhotos: _askForAllPhotos,
        onOpenSettings: _openSettings,
        onCancel: _cancelTo == null ? null : _cancelChoice,
      ),
      // Keys, so switching between the two starts a fresh album list.
      _Showing.allPhotos => AlbumPickerScreen(
        key: const ValueKey(_Showing.allPhotos),
        repository: widget.repository,
        store: widget.store,
        settings: widget.settings,
        accessNote: _status == AccessStatus.limited
            ? 'SwipeSort can only see the photos you selected.'
            : null,
        onAccessAction: widget.repository.changeSelectedPhotos,
        photos: _photoSource,
      ),
      _Showing.folders => AlbumPickerScreen(
        key: const ValueKey(_Showing.folders),
        repository: widget.folders!,
        store: widget.store,
        settings: widget.settings,
        accessNote: 'SwipeSort can only see the folders you chose.',
        accessActionLabel: 'Folders',
        onAccessAction: _manageFolders,
        photos: _photoSource,
      ),
    };
  }
}

/// What should SwipeSort see: a folder, or every photo?
class _ChoiceView extends StatelessWidget {
  const _ChoiceView({
    required this.refused,
    required this.onChooseFolder,
    required this.onAllPhotos,
    required this.onOpenSettings,
    this.onCancel,
  });

  final bool refused;
  final VoidCallback onChooseFolder;
  final VoidCallback onAllPhotos;
  final VoidCallback onOpenSettings;

  /// Goes back without changing anything. Null on first launch, when
  /// there's nothing to go back to.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cancel = onCancel;
    // Android's back gesture cancels too, when there's somewhere to go back
    // to. This screen replaces the album list rather than covering it, so
    // without this, back would close the app.
    return PopScope(
      canPop: cancel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel?.call();
      },
      child: Scaffold(
        appBar: cancel == null
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: cancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                ),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'What should SwipeSort see?',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('You can change this later.', style: quiet),
                    const SizedBox(height: 24),
                    _ChoiceCard(
                      icon: Icons.folder_outlined,
                      title: 'Choose a folder',
                      description:
                          'Only that folder and the folders inside it, such as '
                          'Camera or WhatsApp Images. Nothing else on this '
                          'phone.',
                      onTap: onChooseFolder,
                    ),
                    const SizedBox(height: 12),
                    // Says "or some" because Android's own prompt, behind this
                    // card, also offers picking photos one by one (Android 14+).
                    // The app can't open that picker directly, so this card is
                    // the way to it.
                    _ChoiceCard(
                      icon: Icons.photo_library_outlined,
                      title: 'All photos, or some',
                      description:
                          'Every photo on this phone. On Android 14 and newer '
                          'you can also pick just some.',
                      onTap: onAllPhotos,
                    ),
                    if (refused) ...[
                      const SizedBox(height: 20),
                      Text(
                        "Android didn't allow access to all photos. Choose a "
                        'folder instead, or allow it in Settings.',
                        style: quiet,
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: onOpenSettings,
                          child: const Text('Open settings'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your photos never leave this phone.',
                            style: quiet,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // The app's one accent colour, marking the choices.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessDeniedView extends StatelessWidget {
  const _AccessDeniedView({
    required this.onAllow,
    required this.onOpenSettings,
  });

  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined, size: 64),
              const SizedBox(height: 24),
              Text(
                'SwipeSort needs your photos',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'It shows them to you one at a time so you can decide what '
                'to keep. Your photos never leave this device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onAllow,
                child: const Text('Allow access'),
              ),
              const SizedBox(height: 8),
              // After two refusals Android stops showing its prompt, so
              // Settings is the only way left to allow access.
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
