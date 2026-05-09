import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Retro/arcade-leaning visual identity. Deep navy background, warm amber
/// accent, blocky pixel-style typography. The in-game piece colors (player
/// red, clone amber) are kept consistent with the brand accent so the board
/// feels of-a-piece with the rest of the app.
class PiYingTheme {
  static const Color bg = Color(0xFF0F1B3F); // very deep navy
  static const Color surface = Color(0xFF1B2754); // panel / card
  static const Color surfaceLow = Color(0xFF142046); // sunken / pressed
  static const Color outline = Color(0xFF3A4778); // subtle borders

  static const Color amber = Color(0xFFFFD45A); // brand accent, ui
  static const Color amberDeep = Color(0xFFFBC02D); // clone chip in-game
  static const Color red = Color(0xFFE53935); // player chip in-game / urgent
  static const Color cyan = Color(0xFF3AF5FF); // status / "your turn"

  static const Color onSurface = Color(0xFFF5F0E0); // warm off-white text
  static const Color onSurfaceMuted = Color(0xFF9CA1C2);

  static ThemeData build() {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: amber,
      onPrimary: bg,
      secondary: cyan,
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

    // Display / headline = Press Start 2P (blocky pixel). Body = VT323
    // (readable retro mono). Buttons use the headline font small for the
    // arcade-marquee feel.
    final headlineFont = GoogleFonts.pressStart2pTextTheme(base.textTheme);
    final bodyFont = GoogleFonts.vt323TextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.copyWith(
        displayLarge: headlineFont.displayLarge?.copyWith(
          color: amber,
          letterSpacing: 1.5,
        ),
        displayMedium: headlineFont.displayMedium?.copyWith(color: amber),
        displaySmall: headlineFont.displaySmall?.copyWith(color: amber),
        headlineLarge: headlineFont.headlineLarge?.copyWith(color: amber),
        headlineMedium: headlineFont.headlineMedium?.copyWith(color: amber),
        headlineSmall: headlineFont.headlineSmall?.copyWith(color: amber),
        titleLarge: headlineFont.titleLarge?.copyWith(color: onSurface),
        titleMedium: headlineFont.titleMedium?.copyWith(color: onSurface),
        titleSmall: headlineFont.titleSmall?.copyWith(color: onSurface),
        bodyLarge: bodyFont.bodyLarge?.copyWith(color: onSurface, fontSize: 22),
        bodyMedium: bodyFont.bodyMedium?.copyWith(
          color: onSurface,
          fontSize: 20,
        ),
        bodySmall: bodyFont.bodySmall?.copyWith(
          color: onSurfaceMuted,
          fontSize: 18,
        ),
        labelLarge: headlineFont.labelLarge?.copyWith(color: bg, fontSize: 14),
        labelMedium: headlineFont.labelMedium?.copyWith(
          color: bg,
          fontSize: 12,
        ),
        labelSmall: headlineFont.labelSmall?.copyWith(color: bg, fontSize: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: bg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: GoogleFonts.pressStart2p(fontSize: 14, letterSpacing: 1.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          side: const BorderSide(color: amber, width: 2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.pressStart2p(fontSize: 11, letterSpacing: 1.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: amber,
          textStyle: GoogleFonts.pressStart2p(fontSize: 11),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: amber,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.pressStart2p(
          color: amber,
          fontSize: 16,
          letterSpacing: 1.5,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: outline, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: GoogleFonts.vt323(color: onSurface, fontSize: 20),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
