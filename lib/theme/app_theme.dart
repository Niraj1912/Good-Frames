import 'package:flutter/material.dart';

/// SwipeSort's look, in one place. The rules:
///
/// * Photo first: surfaces are neutral (no tint), so a photo's own colours
///   read true and nothing competes with it.
/// * Colour means something: green keeps, red deletes. Everything else is
///   ink on paper.
/// * Quiet shapes: modest corners and thin borders instead of shadows.
abstract final class AppTheme {
  static final light = _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1B1B1A), // Ink
      onPrimary: Color(0xFFF7F6F3),
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
  );

  static final dark = _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFEDECE8),
      onPrimary: Color(0xFF131313),
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
  );

  /// Digits all the same width, so counters don't wobble as they change.
  static const tabularFigures = [FontFeature.tabularFigures()];

  static ThemeData _build(ColorScheme colors, SortColors sort) {
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
      scaffoldBackgroundColor: colors.surface,
      textTheme: text,
      extensions: [sort],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
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
        color: colors.onSurface,
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
        backgroundColor: colors.surfaceContainerLow,
        dividerColor: colors.outlineVariant,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
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
  });

  static const light = SortColors(
    keep: Color(0xFF2D7A4C),
    delete: Color(0xFFB3372B),
    photoMatte: Color(0xFFE9E7E2),
  );

  static const dark = SortColors(
    keep: Color(0xFF63B482),
    delete: Color(0xFFE2705F),
    photoMatte: Color(0xFF0D0D0D),
  );

  final Color keep;
  final Color delete;

  /// Behind photos that don't fill their frame.
  final Color photoMatte;

  /// The theme's colours, or the defaults if a widget is used outside the
  /// app's theme (in a test, say), so it never crashes for lack of them.
  static SortColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SortColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  SortColors copyWith({Color? keep, Color? delete, Color? photoMatte}) =>
      SortColors(
        keep: keep ?? this.keep,
        delete: delete ?? this.delete,
        photoMatte: photoMatte ?? this.photoMatte,
      );

  // Lets the colours fade smoothly when switching between light and dark.
  @override
  SortColors lerp(SortColors? other, double t) {
    if (other == null) return this;
    return SortColors(
      keep: Color.lerp(keep, other.keep, t)!,
      delete: Color.lerp(delete, other.delete, t)!,
      photoMatte: Color.lerp(photoMatte, other.photoMatte, t)!,
    );
  }
}
