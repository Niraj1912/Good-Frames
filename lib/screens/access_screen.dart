import 'package:flutter/material.dart';
import 'package:photo_swipe/data/decision_store.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/screens/album_picker_screen.dart';

/// The first screen. Asks for photo access, explains if the user refuses,
/// and shows the albums once access is granted.
class AccessScreen extends StatefulWidget {
  const AccessScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final PhotoRepository repository;
  final DecisionStore store;

  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen>
    with WidgetsBindingObserver {
  AccessStatus? _status; // Null while waiting for the user's answer.
  bool _sentToSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestAccess();
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
      _requestAccess();
    }
  }

  Future<void> _requestAccess() async {
    final status = await widget.repository.requestAccess();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _openSettings() async {
    _sentToSettings = true;
    await widget.repository.openAccessSettings();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AccessStatus.denied => _AccessDeniedView(
        onAllow: _requestAccess,
        onOpenSettings: _openSettings,
      ),
      final status => AlbumPickerScreen(
        repository: widget.repository,
        store: widget.store,
        limitedAccess: status == AccessStatus.limited,
      ),
    };
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
