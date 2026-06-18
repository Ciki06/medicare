import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const primaryBlue = Color(0xFF315CF4);
  static const navy = Color(0xFF193D82);
  static const green = Color(0xFF61A654);
  static const lightBlue = Color(0xFFE4F1FC);
  static const paleBlue = Color(0xFFDDECF8);
  static const text = Color(0xFF14171C);
  static const muted = Color(0xFF7D8188);
  static const border = Color(0xFFC7C9CC);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: primaryBlue),
    scaffoldBackgroundColor: const Color(0xFFF4F4F4),
    fontFamily: 'Arial',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: text,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(
        color: text,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: TextStyle(color: text, fontSize: 14),
      bodySmall: TextStyle(color: muted, fontSize: 11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 12),
      prefixIconColor: const Color(0xFF858585),
      suffixIconColor: const Color(0xFF858585),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: primaryBlue, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
