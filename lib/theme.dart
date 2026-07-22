import 'package:flutter/material.dart';

/// Maherai Music design tokens — dark-first, one accent, 8pt spacing grid.
abstract final class MTheme {
  static const bg = Color(0xFF0B0B10);
  static const surface = Color(0xFF16161E);
  static const surfaceHigh = Color(0xFF1F1F2A);
  static const accent = Color(0xFFFF4D67);
  static const accentSoft = Color(0x1AFF4D67); // accent @ 10%

  static const textHigh = Color(0xFFFFFFFF);
  static Color get textMid => Colors.white.withValues(alpha: 0.72);
  static Color get textLow => Colors.white.withValues(alpha: 0.48);

  static const radiusCard = 20.0;
  static const radiusTile = 12.0;

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: bg,
        primary: accent,
      ),
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textHigh,
        displayColor: textHigh,
        fontFamilyFallback: const ['SF Pro Text', 'Roboto'],
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textHigh,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textHigh),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.16),
        trackHeight: 3,
      ),
    );
  }
}
