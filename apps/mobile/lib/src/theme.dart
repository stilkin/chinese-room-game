import 'package:flutter/material.dart';

/// Retro-76 leaning visual identity. Near-black background, three high-contrast
/// primaries (red, yellow, blue), warm-white text. Multi-color is part of the
/// brand; the palette is intentionally bigger than a typical dark Material
/// theme.
///
/// The in-game piece colors (player red, clone yellow) are part of the same
/// palette as the UI accent (blue), so the board feels of-a-piece with the
/// rest of the app — and we never put the same color on two semantically
/// different things.
class PiYingTheme {
  // Near-black background — slightly tinted to feel warm rather than clinical.
  // VHS-tape-cassette dark, not "OS dark mode."
  static const Color bg = Color(0xFF12121A);
  static const Color surface = Color(0xFF1E1E28); // panel / card
  static const Color surfaceLow = Color(0xFF0A0A0E); // sunken / under-board
  static const Color outline = Color(0xFF4A4A55); // visible borders, readable

  // Three primaries.
  static const Color red = Color(0xFFFF3D2E); // player chip, urgent
  static const Color yellow = Color(0xFFFFC700); // clone chip, brand accent
  static const Color blue = Color(
    0xFF2A7FE8,
  ); // ui accent, buttons, "your turn"

  // Aliases used by older code paths so we don't have to refactor every call
  // site that referenced amber / amberDeep.
  static const Color amber = yellow;
  static const Color amberDeep = yellow;
  static const Color cyan = blue;

  // Text. Warm white instead of pure white for the slightly-VHS feel; muted
  // is intentionally still readable on bg (passes WCAG-ish for 18px+ text).
  static const Color onSurface = Color(0xFFF5F0E0);
  static const Color onSurfaceMuted = Color(0xFFB5B0A8);

  static const String _headlineFamily = 'PressStart2P';
  static const String _bodyFamily = 'VT323';

  static ThemeData build() {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: blue,
      onPrimary: onSurface,
      secondary: yellow,
      onSecondary: bg,
      tertiary: red,
      onTertiary: onSurface,
      error: red,
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
        // Headlines / titles: Press Start 2P. Used sparingly because at large
        // sizes the pixel letters take a lot of horizontal room.
        displayLarge: _headline(28, color: yellow, letterSpacing: 1.5),
        displayMedium: _headline(22, color: yellow, letterSpacing: 1.5),
        displaySmall: _headline(18, color: yellow, letterSpacing: 1.0),
        headlineLarge: _headline(20, color: yellow, letterSpacing: 1.5),
        headlineMedium: _headline(16, color: yellow, letterSpacing: 1.5),
        headlineSmall: _headline(14, color: yellow, letterSpacing: 1.0),
        titleLarge: _headline(14, color: onSurface, letterSpacing: 1.0),
        titleMedium: _headline(12, color: onSurface, letterSpacing: 1.0),
        titleSmall: _headline(10, color: onSurface, letterSpacing: 1.5),
        // Body text: VT323. Larger sizes than usual because the font is on
        // the small side at typical body sizes.
        bodyLarge: _body(22, color: onSurface),
        bodyMedium: _body(20, color: onSurface),
        bodySmall: _body(18, color: onSurfaceMuted),
        labelLarge: _headline(12, color: bg, letterSpacing: 1.5),
        labelMedium: _headline(11, color: bg, letterSpacing: 1.0),
        labelSmall: _headline(10, color: bg, letterSpacing: 1.0),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: yellow,
          foregroundColor: bg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: _headline(13, color: bg, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: yellow,
          side: const BorderSide(color: yellow, width: 2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: _headline(11, color: yellow, letterSpacing: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: yellow,
          textStyle: _headline(10, color: yellow),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: yellow,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _headline(16, color: yellow, letterSpacing: 2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: yellow, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: _body(20, color: onSurface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: outline, width: 2),
        ),
      ),
    );
  }

  static TextStyle _headline(
    double size, {
    Color? color,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: _headlineFamily,
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    height: 1.4,
  );

  static TextStyle _body(double size, {Color? color}) => TextStyle(
    fontFamily: _bodyFamily,
    fontSize: size,
    color: color,
    height: 1.2,
  );
}
