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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _Section(
              title: 'Sorting',
              children: [
                ListTile(
                  leading: const _IconTile(Icons.swap_horiz),
                  title: const Text('Swipe directions'),
                  subtitle: Text(_keepSideLabels[_settings.keepSide]!),
                  onTap: _chooseKeepSide,
                ),
                ListTile(
                  leading: const _IconTile(Icons.sort),
                  title: const Text('Order'),
                  subtitle: Text(_orderLabels[_settings.order]!),
                  onTap: _chooseOrder,
                ),
                SwitchListTile(
                  secondary: const _IconTile(Icons.vibration),
                  title: const Text('Vibration'),
                  subtitle: const Text(
                    'A small buzz when letting go will count',
                  ),
                  value: _settings.vibration,
                  onChanged: (on) => _change(() => _settings.setVibration(on)),
                ),
              ],
            ),
            _Section(
              title: 'Look',
              children: [
                ListTile(
                  leading: const _IconTile(Icons.contrast),
                  title: const Text('Theme'),
                  subtitle: Text(_themeLabels[_settings.theme]!),
                  onTap: _chooseTheme,
                ),
              ],
            ),
            if (widget.photos case final photos?)
              _Section(
                title: 'Photos',
                children: [
                  ListTile(
                    leading: const _IconTile(Icons.photo_library_outlined),
                    title: const Text('What SwipeSort sees'),
                    subtitle: Text(photos.summary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePhotos(photos),
                  ),
                ],
              ),
            FutureBuilder(
              future: _version,
              builder: (context, snapshot) => _Section(
                title: 'About',
                children: [
                  if (snapshot.data case final version?)
                    ListTile(
                      leading: const _IconTile(Icons.info_outline),
                      title: const Text('Version'),
                      subtitle: Text(version),
                    ),
                  // The packages SwipeSort is built from are free on one
                  // condition: their licence notices go with the app.
                  // Flutter collects them all on this page.
                  ListTile(
                    leading: const _IconTile(Icons.description_outlined),
                    title: const Text('Open-source licenses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showLicences(snapshot.data),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
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

/// A group of settings: a small heading in the accent colour, over a card
/// holding the group's rows.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(color: colors.primary),
          ),
        ),
        Material(
          // A step lighter than the page in light mode, darker in dark.
          color: theme.brightness == Brightness.light
              ? colors.surfaceContainerLowest
              : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A setting's icon on a soft square of the accent colour.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
      ),
    );
  }
}
