import 'package:flutter/material.dart';
import 'package:photo_swipe/data/app_info.dart';
import 'package:photo_swipe/models/keep_side.dart';
import 'package:photo_swipe/models/photo_order.dart';
import 'package:photo_swipe/state/settings.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/widgets/large_title_bar.dart';

/// What Good Frames can see, in a few words, and what to do to change it.
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
              "Couldn't save that setting. It applies until Good Frames closes.",
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

  // A sheet sliding up from the bottom, listing [options] with [current]
  // ticked. Picking one closes it; returns null if the user backs out.
  Future<T?> _pick<T>({
    required String title,
    required T current,
    required Map<T, String> options,
  }) => showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // As tall as it needs, even with very large text.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Glass(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          tint: GlassColors.of(context).overPhotos,
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The grab handle that says the sheet can be swiped away.
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  RadioGroup<T>(
                    groupValue: current,
                    onChanged: (value) => Navigator.pop(context, value),
                    child: Column(
                      children: [
                        for (final MapEntry(key: value, value: label)
                            in options.entries)
                          RadioListTile<T>(value: value, title: Text(label)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Changing what Good Frames sees changes the album list, so go back to it
  // first and make the change from there.
  void _changePhotos(PhotoSource photos) {
    Navigator.of(context).pop();
    photos.change();
  }

  Future<void> _showLicences(String? version) async => showLicensePage(
    context: context,
    applicationName: 'Good Frames',
    applicationVersion: version,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      body: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => CustomScrollView(
          slivers: [
            const LargeTitleBar(title: 'Settings'),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.list(
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
                        onChanged: (on) =>
                            _change(() => _settings.setVibration(on)),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Look',
                    footer: 'Auto follows your phone.',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const _IconTile(Icons.contrast),
                                const SizedBox(width: 16),
                                Text('Theme', style: theme.textTheme.bodyLarge),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _Segmented<ThemeMode>(
                              value: _settings.theme,
                              options: _themeLabels,
                              onChanged: (mode) =>
                                  _change(() => _settings.setTheme(mode)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.photos case final photos?)
                    _Section(
                      title: 'Photos',
                      children: [
                        ListTile(
                          leading: const _IconTile(
                            Icons.photo_library_outlined,
                          ),
                          title: const Text('What Good Frames sees'),
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
                        // The packages Good Frames is built from are free on
                        // one condition: their licence notices go with the
                        // app. Flutter collects them all on this page.
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
  ThemeMode.system: 'Auto',
  ThemeMode.light: 'Light',
  ThemeMode.dark: 'Dark',
};

/// A group of settings, the way iOS lays them out: a small grey heading,
/// then one rounded pane of glass with the rows in it, a hairline between
/// them that starts after the icon, and an optional footnote underneath.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
          child: Text(title, style: quiet),
        ),
        Glass(
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 66,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer case final footer?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(footer, style: quiet),
          ),
      ],
    );
  }
}

/// A setting's icon on a soft rounded square of the accent colour.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
      ),
    );
  }
}

/// A row of choices in one capsule, with the chosen one raised, so a choice
/// of two or three things takes a tap rather than a pop-up.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final MapEntry(key: option, value: label) in options.entries)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: option == value,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: option == value
                            ? (theme.brightness == Brightness.light
                                  ? colors.surfaceContainerLowest
                                  : colors.surfaceContainerHighest)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: option == value
                            ? const [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: option == value
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
