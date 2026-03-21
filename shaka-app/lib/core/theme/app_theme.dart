import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Shaka App Theme
///
/// Design: Clean Ocean
/// - Confident weights for mobile legibility
/// - Tight letter-spacing on labels for readability
/// - Warmth on light surfaces, cool-blue tint on dark surfaces
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

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 48,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
          height: 1.1,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
          height: 1.1,
        ),
        displaySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
          height: 1.2,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: -0.1,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 0,
        ),
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
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: 1.0,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          letterSpacing: 1.0,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
          letterSpacing: 1.2,
        ),
      ),

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

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

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

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.oceanBlue,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  /// Dark theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.oceanBlue,
      scaffoldBackgroundColor: AppColors.darkBackground,
      
      colorScheme: const ColorScheme.dark(
        primary: AppColors.oceanBlue,
        secondary: AppColors.coral,
        surface: AppColors.darkSurface,
        surfaceContainerHighest: AppColors.darkBackground,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),

      textTheme: TextTheme(
        displayLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 48,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: -1.0,
          height: 1.1,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: -0.5,
          height: 1.1,
        ),
        displaySmall: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: -0.3,
          height: 1.2,
        ),
        headlineLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: -0.2,
        ),
        headlineMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: -0.1,
        ),
        headlineSmall: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.darkTextSecondary,
          letterSpacing: 0.3,
        ),
        bodyLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1.6,
        ),
        bodyMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.darkTextSecondary,
          letterSpacing: 0.2,
          height: 1.4,
        ),
        labelLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 1.0,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.darkTextSecondary,
          letterSpacing: 1.0,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.darkTextMuted,
          letterSpacing: 1.2,
        ),
      ),

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

      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.oceanBlue, width: 2),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.darkTextMuted,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkBackground,
        selectedItemColor: AppColors.oceanBlue,
        unselectedItemColor: AppColors.darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
