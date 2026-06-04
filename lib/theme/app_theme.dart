import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._(); // prevent instantiation

  // ── Brand & Core Colors ───────────────────────────────────────────────────
  static const Color primaryBlue = Color(
    0xFF1967D2,
  ); // Main button and branding blue
  static const Color backgroundLight = Color(
    0xFFF8FAFC,
  ); // Clean background shade
  static const Color borderGrey = Color(0xFFE2E8F0); // Input border color
  static const Color surfaceWhite = Colors.white;

  // ── Role-Specific Colors ──────────────────────────────────────────────────
  // Used for text, borders, and accents based on the selected user role
  static const Color patientColor = Color(0xFF1967D2); // Patient accent blue
  static const Color caregiverColor = Color(
    0xFF2E7D32,
  ); // Caregiver admin green
  static const Color familyColor = Color(0xFF7B1FA2); // Family purple
  static const Color pharmacyColor = Color(
    0xFFE65100,
  ); // Pharmacy orange/yellow

  // ── Status Colors ──────────────────────────────────────────────────────────
  static const Color statusSuccess = Color(
    0xFF4CAF50,
  ); // Taken / Correct Medicine green
  static const Color statusError = Color(0xFFD32F2F); // Missed / Emergency red
  static const Color alertBackground = Color(
    0xFFFFEBEE,
  ); // Emergency overlay tint

  // ── Text Colors ────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(
    0xFF0F172A,
  ); // Main headers and heavy text
  static const Color textSecondary = Color(
    0xFF64748B,
  ); // Form hints, descriptions, labels
  static const Color textOnPrimary = Colors.white; // Text inside filled buttons

  // ── Text Theme ─────────────────────────────────────────────────────────────
  static const TextTheme appTextTheme = TextTheme(
    // Large Welcome Back! / Create Account titles
    headlineLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    // Section headers, card main titles (e.g., "Choose Your Role")
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    // Main field input labels (e.g., "Full Name", "Email")
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    // Standard descriptive body text and input field inputs
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: textPrimary,
    ),
    // Secondary text descriptions, subtitles, role details
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textSecondary,
    ),
    // Small legal text, footer links, or tiny metadata captions
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: textSecondary,
    ),
    // Text strictly designated for button actions
    labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: textOnPrimary,
    ),
  );

  // ── Component Themes ───────────────────────────────────────────────────────

  // Universal button style configuration matching the main auth actions
  static final ElevatedButtonThemeData elevatedButtonTheme =
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: textOnPrimary,
          minimumSize: const Size(double.infinity, 52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  // Unified Text Field styling for inputs seen in screens 2 and 3
  static final InputDecorationTheme inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: surfaceWhite,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    hintStyle: const TextStyle(color: textSecondary, fontSize: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: borderGrey),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: borderGrey),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryBlue, width: 2),
    ),
  );

  // ── Primary App Theme ──────────────────────────────────────────────────────

  // Use as the base light configuration inside your MaterialApp
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: backgroundLight,
    primaryColor: primaryBlue,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
      background: backgroundLight,
    ),
    textTheme: appTextTheme,
    elevatedButtonTheme: elevatedButtonTheme,
    inputDecorationTheme: inputDecorationTheme,
  );
}
