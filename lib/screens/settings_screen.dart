import 'package:flutter/material.dart';
import 'package:photo_swipe/data/app_info.dart';
import 'package:photo_swipe/models/keep_side.dart';
import 'package:photo_swipe/models/photo_order.dart';
import 'package:photo_swipe/state/settings.dart';

/// What SwipeSort can see, in a few words, and what to do to change it.
typedef PhotoSource = ({String summary, VoidCallback change});

/// The app's few settings. Each change applies at once and is saved.
///
/// Kept short on purpose: every setting is a question the user has to
/// answer, so only things people really disagree about are here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, this.photos});

  final Settings settings;

  /// Null where there's no choice to make, as on Windows.
  final PhotoSource? photos;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<String?> _version = AppInfo.version();

  Settings get _settings => widget.settings;

  // Applies a change. If it can't be saved, it still applies until the app
  // closes, so just say so.
  Future<void> _change(Future<void> Function() change) async {
    try {
      await change();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't save that setting. It applies until SwipeSort closes.",
            ),
          ),
        );
    }
  }

  Future<void> _chooseKeepSide() async {
    final side = await _pick(
      title: 'Swipe directions',
      current: _settings.keepSide,
      options: _keepSideLabels,
    );
    if (side != null) await _change(() => _settings.setKeepSide(side));
  }

  Future<void> _chooseOrder() async {
    final order = await _pick(
      title: 'Order',
      current: _settings.order,
      options: _orderLabels,
    );
    if (order != null) await _change(() => _settings.setOrder(order));
  }

  Future<void> _chooseTheme() async {
    final theme = await _pick(
      title: 'Theme',
      current: _settings.theme,
      options: _themeLabels,
    );
    if (theme != null) await _change(() => _settings.setTheme(theme));
  }

  // A dialog listing [options], with [current] ticked. Picking one closes
  // it; returns null if the user backs out.
  Future<T?> _pick<T>({
    required String title,
    required T current,
    required Map<T, String> options,
  }) => showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<T>(
          groupValue: current,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            children: [
              for (final MapEntry(key: value, value: label) in options.entries)
                RadioListTile<T>(value: value, title: Text(label)),
            ],
          ),
        ),
      ],
    ),
  );

  // Changing what SwipeSort sees changes the album list, so go back to it
  // first and make the change from there.
  void _changePhotos(PhotoSource photos) {
    Navigator.of(context).pop();
    photos.change();
  }

  Future<void> _showLicences(String? version) async => showLicensePage(
    context: context,
    applicationName: 'SwipeSort',
    applicationVersion: version,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _SectionTitle('Sorting'),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Swipe directions'),
              subtitle: Text(_keepSideLabels[_settings.keepSide]!),
              onTap: _chooseKeepSide,
            ),
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('Order'),
              subtitle: Text(_orderLabels[_settings.order]!),
              onTap: _chooseOrder,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Vibration'),
              subtitle: const Text('A small buzz when letting go will count'),
              value: _settings.vibration,
              onChanged: (on) => _change(() => _settings.setVibration(on)),
            ),
            const _SectionTitle('Look'),
            ListTile(
              leading: const Icon(Icons.contrast),
              title: const Text('Theme'),
              subtitle: Text(_themeLabels[_settings.theme]!),
              onTap: _chooseTheme,
            ),
            if (widget.photos case final photos?) ...[
              const _SectionTitle('Photos'),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('What SwipeSort sees'),
                subtitle: Text(photos.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _changePhotos(photos),
              ),
            ],
            const _SectionTitle('About'),
            FutureBuilder(
              future: _version,
              builder: (context, snapshot) => Column(
                children: [
                  if (snapshot.data case final version?)
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Version'),
                      subtitle: Text(version),
                    ),
                  // The packages SwipeSort is built from are free on one
                  // condition: their licence notices go with the app.
                  // Flutter collects them all on this page.
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Open-source licenses'),
                    onTap: () => _showLicences(snapshot.data),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }
}

const _keepSideLabels = {
  KeepSide.right: 'Right keeps, left deletes',
  KeepSide.left: 'Left keeps, right deletes',
};

const _orderLabels = {
  PhotoOrder.newestFirst: 'Newest first',
  PhotoOrder.oldestFirst: 'Oldest first',
};

const _themeLabels = {
  ThemeMode.system: 'Same as phone',
  ThemeMode.light: 'Light',
  ThemeMode.dark: 'Dark',
};

/// A small heading over each group of settings, in the app's accent colour.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
