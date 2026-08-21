import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_settings.dart';

/// Warm graphite dark with soft champagne text — calmer than neon gold on navy.
class AppTheme {
  static const _ink = Color(0xFFE6DCC8);
  static const _inkMuted = Color(0xFFA89F8C);
  static const _surface = Color(0xFF16141A);
  static const _surfaceRaised = Color(0xFF221F28);
  static const _bubbleIn = Color(0xFF2A2732);
  static const _bubbleOut = Color(0xFF3A3428);

  static Color get bubbleIncoming => _bubbleIn;
  static Color get bubbleOutgoing => _bubbleOut;

  static (Color primary, Color accent) colorsFor(AppAccentColor accent) {
    return switch (accent) {
      AppAccentColor.gold => (const Color(0xFFC6A15B), const Color(0xFFD8B56A)),
      AppAccentColor.amber => (const Color(0xFFE5A845), const Color(0xFFF0BC5A)),
      AppAccentColor.sage => (const Color(0xFF8FAF8A), const Color(0xFFA8C4A3)),
      AppAccentColor.rose => (const Color(0xFFD4848A), const Color(0xFFE8A0A6)),
      AppAccentColor.sky => (const Color(0xFF7BAFD4), const Color(0xFF95C4E8)),
    };
  }

  static ThemeData light({AppAccentColor accent = AppAccentColor.gold}) {
    final (primary, accentColor) = colorsFor(accent);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: const Color(0xFF1A1408),
      secondary: accentColor,
      surface: const Color(0xFFF6F1E8),
      onSurface: const Color(0xFF2A2418),
      surfaceContainerHighest: const Color(0xFFE8E0D2),
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark({AppAccentColor accent = AppAccentColor.gold}) {
    final (primary, accentColor) = colorsFor(accent);
    final scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: const Color(0xFF1A1408),
      secondary: accentColor,
      onSecondary: const Color(0xFF1A1408),
      surface: _surface,
      onSurface: _ink,
      onSurfaceVariant: _inkMuted,
      surfaceContainerHighest: _surfaceRaised,
      outline: const Color(0xFF4A4555),
      outlineVariant: const Color(0xFF332F3A),
      error: const Color(0xFFE08A8A),
      onError: const Color(0xFF1A0808),
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final textTheme = GoogleFonts.ibmPlexSansTextTheme(
      brightness == Brightness.dark
          ? ThemeData(brightness: Brightness.dark).textTheme
          : ThemeData(brightness: Brightness.light).textTheme,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: scheme.onSurface),
      primaryIconTheme: IconThemeData(color: scheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: GoogleFonts.ibmPlexSerif(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.7), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.ibmPlexSans(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        textColor: scheme.onSurface,
        iconColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
