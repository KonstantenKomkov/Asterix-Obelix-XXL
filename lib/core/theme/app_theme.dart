import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const ink = Color(0xFF101A27);
  static const navy = Color(0xFF17283D);
  static const gold = Color(0xFFF2B544);
  static const parchment = Color(0xFFFFE8B0);
  static const red = Color(0xFFB93B34);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
      surface: navy,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      useMaterial3: true,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: parchment,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
        headlineMedium: TextStyle(
          color: parchment,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: ink,
          minimumSize: const Size(240, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
