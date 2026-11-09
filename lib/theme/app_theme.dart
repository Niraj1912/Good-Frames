import 'package:flutter/material.dart';
import 'package:good_frames/theme/glass.dart';
import 'package:good_frames/theme/photo_tint.dart';
import 'package:good_frames/widgets/large_title_bar.dart';

/// Good Frames' look, in one place. The rules:
///
/// * Glass: every screen sits on one still background of soft colour
///   ([GlassBackground]), and panels, bars and cards are frosted glass over
///   it ([Glass]). Pages are see-through, so they fade over the background
///   rather than replacing it. Album names sit on glass tinted with their
///   cover's colour ([PhotoTint]).
/// * Photos stay clear: never blurred or tinted, at their own shape.
/// * Colour means something: green keeps, red deletes, and one ink-blue
///   accent marks other actions and choices. Buttons stay solid on the
///   glass, so they're always easy to read.
/// * Quiet shapes: generous, soft corners and hairline edges instead of
///   shadows.
/// * Apple-style structure: Bricolage type on an iPhone-like scale, a big title
///   that shrinks into a blurred bar as lists scroll ([LargeTitleBar]),
///   grouped settings rows, sheets with a grab handle, and one capsule of
///   glass for a screen's top buttons.
abstract final class AppTheme {
  static final light = _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF36766D), // Eucalyptus teal, the one accent
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE0EEEA), // Behind icons that mark a choice
      onPrimaryContainer: Color(0xFF285F58),
      secondary: Color(0xFF53666D),
      onSecondary: Color(0xFFFFFFFF),
      error: Color(0xFFB6404A), // The delete colour
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF6E4E5),
      onErrorContainer: Color(0xFF6B1F26),
      surface: Color(0xFFF2F5F4), // Daylight
      onSurface: Color(0xFF17242A),
      onSurfaceVariant: Color(0xFF53666D),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFEEF3F2),
      surfaceContainer: Color(0xFFEAF0EF),
      surfaceContainerHigh: Color(0xFFE7ECEB),
      surfaceContainerHighest: Color(0xFFE1EAE8),
      outline: Color(0xFFBCCBC8),
      outlineVariant: Color(0xFFDDE5E3),
    ),
    SortColors.light,
    GlassColors.light,
  );

  static final dark = _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF82C8BC),
      onPrimary: Color(0xFF10201F),
      primaryContainer: Color(0xFF1D393A),
      onPrimaryContainer: Color(0xFF95D4CA),
      secondary: Color(0xFFB4C2C6),
      onSecondary: Color(0xFF101820),
      error: Color(0xFFF08B91),
      onError: Color(0xFF281316),
      errorContainer: Color(0xFF3A1D21),
      onErrorContainer: Color(0xFFF6D3D5),
      surface: Color(0xFF101820), // Midnight
      onSurface: Color(0xFFE8EFF0),
      onSurfaceVariant: Color(0xFFB4C2C6),
      surfaceContainerLowest: Color(0xFF0B1117),
      surfaceContainerLow: Color(0xFF192630),
      surfaceContainer: Color(0xFF1C2B34),
      surfaceContainerHigh: Color(0xFF21323D),
      surfaceContainerHighest: Color(0xFF263B47),
      outline: Color(0xFF344954),
      outlineVariant: Color(0x16FFFFFF),
    ),
    SortColors.dark,
    GlassColors.dark,
  );

  /// Frame numbers and other small counts: condensed, like the print on the
  /// edge of a film. Pass a size and colour with copyWith.
  static const edgePrint = TextStyle(
    fontFamily: 'BarlowCondensed',
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Digits all the same width, so counters don't wobble as they change.
  static const tabularFigures = [FontFeature.tabularFigures()];

  /// How solid a tinted pane of glass is, such as an album's: enough of
  /// the background shows through to read as glass, and text on it stays
  /// readable whatever is behind.
  static const tintedGlass = 0.6;

  static ThemeData _build(
    ColorScheme colors,
    SortColors sort,
    GlassColors glass,
  ) {
    final base = ThemeData(colorScheme: colors, fontFamily: 'Bricolage');
    // An Apple-like scale: a big bold title, 17 for reading, 15 and 13 for
    // the smaller things, with the tighter spacing large type needs.
    final text = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 17,
        letterSpacing: -0.2,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        letterSpacing: -0.1,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    const corners = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );

    return base.copyWith(
      // See-through, so every page shows the glass background under it.
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: text,
      extensions: [sort, glass],
      // The chevron back button in the accent colour, as on an iPhone.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: colors.primary,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium?.copyWith(color: colors.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: corners,
          minimumSize: const Size(64, 52),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: corners,
          minimumSize: const Size(64, 52),
          side: BorderSide(color: colors.outline),
          foregroundColor: colors.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      listTileTheme: ListTileThemeData(iconColor: colors.onSurfaceVariant),
      // The accent when on, like an iPhone's green.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurface.withValues(alpha: 0.18),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.outlineVariant,
        linearMinHeight: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: colors.surface),
        shape: corners,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.brightness == Brightness.light
            ? colors.surfaceContainerLowest
            : colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: glass.fill,
        dividerColor: Colors.transparent,
      ),
      // Pages fade and slide over the still background, with nothing
      // painted behind them in between.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
        },
      ),
    );
  }
}

/// Colours with a meaning, beyond what Material's scheme has slots for.
/// Read them with `SortColors.of(context)`.
@immutable
class SortColors extends ThemeExtension<SortColors> {
  const SortColors({
    required this.keep,
    required this.delete,
    required this.photoMatte,
    required this.frame,
  });

  // Deep enough to read as text on its own soft wash too (4.5:1 or more).
  static const light = SortColors(
    keep: Color(0xFF267B59),
    delete: Color(0xFFB6404A),
    photoMatte: Color(0xFFE1EAE8),
    frame: Color(0xFF0F181D),
  );

  static const dark = SortColors(
    keep: Color(0xFF48B58A),
    delete: Color(0xFFF08B91),
    photoMatte: Color(0xFF0B1117),
    frame: Color(0xFF0A0F14),
  );

  final Color keep;
  final Color delete;

  /// Behind photos while they load, such as album covers.
  final Color photoMatte;

  /// The card a photo is sorted on: near-black in both modes, because
  /// photos are judged best against dark, as in a darkroom or a viewer.
  final Color frame;

  /// The theme's colours, or the defaults if a widget is used outside the
  /// app's theme (in a test, say), so it never crashes for lack of them.
  static SortColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SortColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  SortColors copyWith({
    Color? keep,
    Color? delete,
    Color? photoMatte,
    Color? frame,
  }) => SortColors(
    keep: keep ?? this.keep,
    delete: delete ?? this.delete,
    photoMatte: photoMatte ?? this.photoMatte,
    frame: frame ?? this.frame,
  );

  // Lets the colours fade smoothly when switching between light and dark.
  @override
  SortColors lerp(SortColors? other, double t) {
    if (other == null) return this;
    return SortColors(
      keep: Color.lerp(keep, other.keep, t)!,
      delete: Color.lerp(delete, other.delete, t)!,
      photoMatte: Color.lerp(photoMatte, other.photoMatte, t)!,
      frame: Color.lerp(frame, other.frame, t)!,
    );
  }
}
