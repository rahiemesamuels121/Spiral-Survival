import 'package:flutter/material.dart';

/// Shared palette for the board, menus and turn cards.
class AppTheme {
  static const Color navy = Color(0xFF101E29);
  static const Color panel = Color(0xFF1B303A);
  static const Color gold = Color(0xFFD8B878);
  static const Color text = Color(0xFFF6EFDF);
  static const Color muted = Color(0xFFB9C6C8);
  static const Color ivory = Color(0xFFF5EEDD);
  static const Color ink = Color(0xFF203C43);
  static const Color teal = Color(0xFF276A65);
  static const Color line = Color(0xFF40545B);
  static const List<Color> playerColors = [
    Color(0xFFD76562),
    Color(0xFF599ED1),
    Color(0xFF60AC85),
    Color(0xFFE2BC61),
    Color(0xFFAD8ACE),
  ];

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: navy,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      onPrimary: navy,
      secondary: Color(0xFF86BCAC),
      onSecondary: navy,
      surface: panel,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: line,
      error: Color(0xFFF2A6A0),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: text, height: 1.45),
      bodyMedium: TextStyle(color: text, height: 1.4),
      bodySmall: TextStyle(color: muted, height: 1.4),
    ),
    dividerColor: line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF142730),
      labelStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: gold, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: navy,
      selectedColor: gold,
      side: const BorderSide(color: line),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: navy,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: line),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
