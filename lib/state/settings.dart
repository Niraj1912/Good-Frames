import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:good_frames/data/decision_store.dart';
import 'package:good_frames/models/keep_side.dart';
import 'package:good_frames/models/photo_order.dart';

/// The user's choices from the Settings screen. Screens read them, and
/// listen so they redraw when one changes (the theme changes at once).
///
/// A change shows straight away and is then saved, so it's still there the
/// next time the app opens.
class Settings extends ChangeNotifier {
  Settings._(this._store, Map<String, String> saved)
    : _keepSide = _byName(KeepSide.values, saved[_keepSideKey], KeepSide.right),
      _order = _byName(
        PhotoOrder.values,
        saved[_orderKey],
        PhotoOrder.newestFirst,
      ),
      _vibration = saved[_vibrationKey] != 'off',
      _theme = _byName(ThemeMode.values, saved[_themeKey], ThemeMode.system);

  /// Loads the saved settings. One that was never changed, or that this
  /// version of the app doesn't understand, gets its default.
  static Future<Settings> load(DecisionStore store) async =>
      Settings._(store, await store.loadSettings());

  final DecisionStore _store;

  // The names they're saved under. Never rename one: people who already
  // changed that setting would lose their choice.
  static const _keepSideKey = 'keepSide';
  static const _orderKey = 'order';
  static const _vibrationKey = 'vibration';
  static const _themeKey = 'theme';

  KeepSide _keepSide;
  PhotoOrder _order;
  bool _vibration;
  ThemeMode _theme;

  /// Which way a swipe keeps a photo.
  KeepSide get keepSide => _keepSide;

  /// The order albums are sorted in.
  PhotoOrder get order => _order;

  /// Whether the phone buzzes softly as a swipe is about to count.
  bool get vibration => _vibration;

  /// Light, dark, or the same as the phone.
  ThemeMode get theme => _theme;

  // Each setter throws if saving fails. The choice still applies until the
  // app closes, so the caller only has to tell the user.
  Future<void> setKeepSide(KeepSide value) =>
      _change(() => _keepSide = value, _keepSideKey, value.name);

  Future<void> setOrder(PhotoOrder value) =>
      _change(() => _order = value, _orderKey, value.name);

  Future<void> setVibration(bool value) =>
      _change(() => _vibration = value, _vibrationKey, value ? 'on' : 'off');

  Future<void> setTheme(ThemeMode value) =>
      _change(() => _theme = value, _themeKey, value.name);

  Future<void> _change(VoidCallback apply, String key, String saved) async {
    apply();
    notifyListeners();
    await _store.saveSetting(key, saved);
  }

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.asNameMap()[name] ?? fallback;
}
