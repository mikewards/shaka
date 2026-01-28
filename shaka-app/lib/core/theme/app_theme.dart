import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Shaka App Theme
/// 
/// Design: Quiet Luxury
/// - Understated elegance, not tech-forward minimalism
/// - Light font weights for display text
/// - Generous letter-spacing on labels (gallery/museum aesthetic)
/// - Warmth throughout
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.oceanBlue,
      scaffoldBackgroundColor: AppColors.background,
      
      colorScheme: const ColorScheme.light(
        primary: AppColors.oceanBlue,
        secondary: AppColors.coral,
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.background,
        error: AppColors.error,
        onPrimary: AppColors.textOnDark,
        onSecondary: AppColors.textOnDark,
        onSurface: AppColors.textPrimary,
      ),

      // App Bar - Clean, minimal
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.3,
        ),
      ),

      // Typography - Light weights for elegance, generous tracking on labels
      textTheme: const TextTheme(
        // Display - Light weight for refined elegance
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 48,
          fontWeight: FontWeight.w300,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
          height: 1.1,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 36,
          fontWeight: FontWeight.w300,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
          height: 1.1,
        ),
        displaySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
          height: 1.2,
        ),
        // Headlines - Medium weight
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.1,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0,
        ),
        // Titles
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.1,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0.2,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
        // Body - Slightly increased letter-spacing for readability
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.2,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: 0.2,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
          height: 1.4,
        ),
        // Labels - ALL-CAPS with generous tracking (gallery aesthetic)
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 1.5,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          letterSpacing: 1.5,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
          letterSpacing: 2.0,
        ),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.oceanBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.oceanBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.oceanBlue, width: 2),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.textMuted,
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.oceanBlue,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
