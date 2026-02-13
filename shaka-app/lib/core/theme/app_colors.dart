import 'package:flutter/material.dart';

/// Shaka Color Palette
/// 
/// Design: Quiet Luxury - Understated elegance
/// Colors should feel like real materials: leather, aged paper, brushed metal, natural stone
/// Warm tones throughout - no pure black or white
class AppColors {
  AppColors._();

  // Primary - Deep Ocean Blue (slightly warmed)
  static const Color oceanBlue = Color(0xFF1E3A5F);
  static const Color oceanBlueLight = Color(0xFF2D4A6F);
  static const Color oceanBlueDark = Color(0xFF152942);

  // Secondary - Muted Coral (desaturated for quiet luxury)
  static const Color coral = Color(0xFFCB8B7A);
  static const Color coralLight = Color(0xFFD9A99C);
  static const Color coralDark = Color(0xFFAA7265);

  // Neutral - Warm Sand tones
  static const Color sand = Color(0xFFF2E6D9);
  static const Color sandLight = Color(0xFFF8F4EE);
  static const Color sandDark = Color(0xFFE5D4C3);

  // Background & Surface - Warm off-whites, never pure white
  static const Color background = Color(0xFFFAF8F5);
  static const Color surface = Color(0xFFFEFDFB);
  static const Color surfaceElevated = Color(0xFFFFFEFC);

  // Text - Warm near-black, never pure black
  static const Color textPrimary = Color(0xFF2C2C2C);
  static const Color textSecondary = Color(0xFF5A5A58);
  static const Color textMuted = Color(0xFF8E8E8A);
  static const Color textOnDark = Color(0xFFFAF9F7);

  // Borders - Warm grays
  static const Color border = Color(0xFFE8E6E1);
  static const Color borderLight = Color(0xFFF3F1ED);
  static const Color borderDark = Color(0xFFD4D2CD);

  // Shaka Score Colors - 5-tier, desaturated natural tones
  static const Color scoreExcellent = Color(0xFF6B8E7D);    // Sage green      - 80-100
  static const Color scoreGood = Color(0xFF8FA98B);          // Muted green     - 60-79
  static const Color scoreAverage = Color(0xFFC9A66B);       // Amber/brass     - 40-59
  static const Color scoreBelowAvg = Color(0xFFC4876B);      // Dusty terracotta- 20-39
  static const Color scorePoor = Color(0xFFB87A7A);          // Dusty rose      - 0-19

  // Status - Desaturated, refined
  static const Color success = Color(0xFF6B8E7D);
  static const Color warning = Color(0xFFC9A66B);
  static const Color error = Color(0xFFB87A7A);
  static const Color info = Color(0xFF7A9BB8);

  /// Get score color based on shaka score value (5-tier, 20-point bands)
  static Color getScoreColor(int score) {
    if (score >= 80) return scoreExcellent;
    if (score >= 60) return scoreGood;
    if (score >= 40) return scoreAverage;
    if (score >= 20) return scoreBelowAvg;
    return scorePoor;
  }

  /// Which tier (1-5) a score falls into
  static int getScoreTier(int score) {
    if (score >= 80) return 5;
    if (score >= 60) return 4;
    if (score >= 40) return 3;
    if (score >= 20) return 2;
    return 1;
  }

  /// Human-readable label for a score
  static String getScoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Average';
    if (score >= 20) return 'Below Avg';
    return 'Poor';
  }

  // ===========================================
  // DARK THEME COLORS
  // ===========================================

  // Dark Theme - Base colors
  static const darkBackground = Color(0xFF0D0D0D);  // Main app background
  static const darkSurface = Color(0xFF1A1A1A);     // Cards, containers, inputs
  static const darkBorder = Color(0xFF2A2A2A);      // Subtle borders
  static const darkAccent = Color(0xFF7A9BB8);      // Primary accent (muted blue-gray, matches Quiet Luxury theme)

  // Dark Theme - Text colors
  static const darkTextPrimary = Colors.white;
  static const darkTextSecondary = Color(0xB3FFFFFF);  // 70% white
  static const darkTextMuted = Color(0x80FFFFFF);      // 50% white
  static const darkTextHint = Color(0x4DFFFFFF);       // 30% white
}
