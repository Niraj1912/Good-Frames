import 'package:flutter/material.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/theme/photo_tint.dart';

/// SwipeSort's look, in one place. The rules:
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
/// * Quiet shapes: modest corners and hairline edges instead of shadows.
abstract final class AppTheme {
  static final light = _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF2D5BA6), // Ink blue, the one accent
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFDCE4F5), // Behind icons that mark a choice
      onPrimaryContainer: Color(0xFF173A73),
      secondary: Color(0xFF5E5D59),
      onSecondary: Color(0xFFF7F6F3),
      error: Color(0xFFB3372B), // Brick red, the delete colour
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF5DFDB),
      onErrorContainer: Color(0xFF5C1710),
      surface: Color(0xFFF7F6F3), // Warm paper
      onSurface: Color(0xFF1B1B1A),
      onSurfaceVariant: Color(0xFF5E5D59),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF1F0EC),
      surfaceContainer: Color(0xFFECEBE6),
      surfaceContainerHigh: Color(0xFFE6E4DF),
      surfaceContainerHighest: Color(0xFFDEDCD6),
      outline: Color(0xFFC6C4BE),
      outlineVariant: Color(0xFFE1DFD9),
    ),
    SortColors.light,
    GlassColors.light,
  );

  static final dark = _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF8FB2EE),
      onPrimary: Color(0xFF0E1A2E),
      primaryContainer: Color(0xFF223A61),
      onPrimaryContainer: Color(0xFFD6E2F8),
      secondary: Color(0xFFA6A49F),
      onSecondary: Color(0xFF131313),
      error: Color(0xFFE2705F),
      onError: Color(0xFF2A0905),
      errorContainer: Color(0xFF4A1A14),
      onErrorContainer: Color(0xFFF5DFDB),
      surface: Color(0xFF131313), // Neutral, not blue-black
      onSurface: Color(0xFFEDECE8),
      onSurfaceVariant: Color(0xFFA6A49F),
      surfaceContainerLowest: Color(0xFF0D0D0D),
      surfaceContainerLow: Color(0xFF1A1A1A),
      surfaceContainer: Color(0xFF1F1F1F),
      surfaceContainerHigh: Color(0xFF262626),
      surfaceContainerHighest: Color(0xFF2E2E2D),
      outline: Color(0xFF4B4A47),
      outlineVariant: Color(0xFF2E2D2B),
    ),
    SortColors.dark,
    GlassColors.dark,
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
    final base = ThemeData(colorScheme: colors);
    final text = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    const corners = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );

    return base.copyWith(
      // See-through, so every page shows the glass background under it.
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: text,
      extensions: [sort, glass],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(color: colors.onSurface),
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
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
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
    keep: Color(0xFF2A7347),
    delete: Color(0xFFB3372B),
    photoMatte: Color(0xFFE9E7E2),
    frame: Color(0xFF1C1C1B),
  );

  static const dark = SortColors(
    keep: Color(0xFF63B482),
    delete: Color(0xFFE2705F),
    photoMatte: Color(0xFF0D0D0D),
    frame: Color(0xFF0A0A0A),
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
