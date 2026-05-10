import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Moonlit-goban identity. Warm-dark wood backgrounds, ivory cream type and
/// stones, a single cinnabar-red accent. Lean into Go's visual culture
/// (wood + ink + sparing seal-red) without crossing into "ornamental Asian"
/// cosplay. The 皮影 (shadow play) lore is a quiet earned moment, not a
/// motif plastered everywhere.
///
/// Single-family typography (Klee One) — contemporary Japanese-influenced
/// face with native CJK glyphs, so 皮影 renders inline alongside Latin
/// without falling back to a system font. Two weights: 400 body, 600 titles.
class PiYingTheme {
  // Backgrounds and surfaces — warm dark palette. Not pure black; the warmth
  // is what makes "moonlit goban" read instead of "generic dark mode".
  static const Color bg = Color(0xFF1A1612);
  static const Color surface = Color(0xFF2A2218);
  static const Color surfaceLow = Color(0xFF100C08);
  static const Color outline = Color(0xFF6A5840);

  // Board surface — aged kaya wood, dark amber. Reads as warm wood against
  // the slightly darker `bg` so the board sits forward visually.
  static const Color boardPanel = Color(0xFF4A3520);

  // Lines, hoshi, and primary text share the same cream tone. Visual rhyme:
  // the player's stones use this colour too, so the player's pieces feel
  // continuous with the typography.
  static const Color lineColor = Color(0xFFD4B886);

  // Type colours.
  static const Color onSurface = Color(0xFFEAD8B5);
  static const Color onSurfaceMuted = Color(0xFF9A8B6F);

  // The single accent. Used for last-move ring, win callout, destructive UI.
  // Anywhere this colour appears, it should *mean* something — using it for
  // mere decoration dilutes the language.
  static const Color cinnabar = Color(0xFFC13C2B);

  static ThemeData build() {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: cinnabar,
      onPrimary: onSurface,
      secondary: lineColor,
      onSecondary: bg,
      tertiary: lineColor,
      onTertiary: bg,
      error: cinnabar,
      onError: onSurface,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceLow,
      onSurfaceVariant: onSurfaceMuted,
      outline: outline,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: TextTheme(
        // Display / headline / title — all set in Klee One semibold (600),
        // the title weight. Sizes mirror the prior scale's logical structure
        // but tuned for a handwritten serif rather than an 8-bit pixel grid.
        displayLarge: _title(32, color: onSurface, letterSpacing: 1.5),
        displayMedium: _title(26, color: onSurface, letterSpacing: 1.2),
        displaySmall: _title(20, color: onSurface, letterSpacing: 1.0),
        headlineLarge: _title(22, color: onSurface, letterSpacing: 1.0),
        headlineMedium: _title(18, color: onSurface, letterSpacing: 0.8),
        headlineSmall: _title(16, color: onSurface, letterSpacing: 0.5),
        titleLarge: _title(16, color: onSurface, letterSpacing: 1.0),
        titleMedium: _title(14, color: onSurface, letterSpacing: 1.0),
        titleSmall: _title(13, color: onSurfaceMuted, letterSpacing: 1.5),
        // Body — Klee One regular (400).
        bodyLarge: _body(16, color: onSurface),
        bodyMedium: _body(14, color: onSurface),
        bodySmall: _body(12, color: onSurfaceMuted),
        labelLarge: _title(14, color: onSurface, letterSpacing: 1.5),
        labelMedium: _title(12, color: onSurface, letterSpacing: 1.0),
        labelSmall: _title(11, color: onSurfaceMuted, letterSpacing: 1.0),
      ),
      // Button text styles must NOT bake a color — `textStyle.color` takes
      // precedence over `foregroundColor`, so a per-button override (e.g. the
      // cinnabar Delete button on the settings screen) gets silently
      // squashed otherwise. Font / size / spacing only here; colour comes
      // from `foregroundColor`.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cinnabar,
          foregroundColor: onSurface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          textStyle: _title(14, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: const BorderSide(color: outline, width: 1),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: _title(13, letterSpacing: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          textStyle: _title(12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _title(16, color: onSurface, letterSpacing: 2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: outline, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: _body(14, color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: outline, width: 1),
        ),
      ),
    );
  }

  static TextStyle _title(
    double size, {
    Color? color,
    double letterSpacing = 0,
  }) => GoogleFonts.kleeOne(
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: letterSpacing,
    height: 1.4,
  );

  static TextStyle _body(double size, {Color? color}) => GoogleFonts.kleeOne(
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );
}
