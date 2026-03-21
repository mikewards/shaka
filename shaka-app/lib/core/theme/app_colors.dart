import 'package:flutter/material.dart';

/// Shaka Color Palette
///
/// Design: Clean Ocean — bright, confident data indicators on calm backgrounds.
/// Scores and interactive elements pop; backgrounds and borders stay subtle.
class AppColors {
  AppColors._();

  // Primary - True Ocean Blue
  static const Color oceanBlue = Color(0xFF1B6FA8);
  static const Color oceanBlueLight = Color(0xFF2E8BC0);
  static const Color oceanBlueDark = Color(0xFF0E4D76);

  // Secondary - Punchy Coral
  static const Color coral = Color(0xFFE8735A);
  static const Color coralLight = Color(0xFFF09A85);
  static const Color coralDark = Color(0xFFC45A42);

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

  // Shaka Score Colors - Apple-inspired 5-tier palette
  static const Color scoreExcellent = Color(0xFF30D158);    // Apple Green     - 80-100
  static const Color scoreGood = Color(0xFF7AE02B);          // Chartreuse      - 60-79
  static const Color scoreAverage = Color(0xFFFFD60A);       // Apple Yellow    - 40-59
  static const Color scoreBelowAvg = Color(0xFFFF9F0A);      // Apple Orange    - 20-39
  static const Color scorePoor = Color(0xFFFF453A);          // Apple Red       - 0-19

  // Score background tints (13% opacity for chip/badge backgrounds)
  static const Color scoreExcellentBg = Color(0x2230D158);
  static const Color scoreGoodBg = Color(0x227AE02B);
  static const Color scoreAverageBg = Color(0x22FFD60A);
  static const Color scoreBelowAvgBg = Color(0x22FF9F0A);
  static const Color scorePoorBg = Color(0x22FF453A);

  // Status
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color error = Color(0xFFFF453A);
  static const Color info = Color(0xFF38BDF8);

  // Chart / condition indicator colors
  static const Color chartTide = Color(0xFF38BDF8);
  static const Color chartTideHigh = Color(0xFF2DD4BF);
  static const Color chartTideLow = Color(0xFF60A5FA);
  static const Color chartNowLine = Color(0xFFFBBF24);
  static const Color chartSwell = Color(0xFFD4A037);
  static const Color chartWind = Color(0xFF607D8B);

  /// Get score color based on shaka score value (5-tier, 20-point bands)
  static Color getScoreColor(int score) {
    if (score >= 80) return scoreExcellent;
    if (score >= 60) return scoreGood;
    if (score >= 40) return scoreAverage;
    if (score >= 20) return scoreBelowAvg;
    return scorePoor;
  }

  /// Get score background tint for chips/badges
  static Color getScoreBgColor(int score) {
    if (score >= 80) return scoreExcellentBg;
    if (score >= 60) return scoreGoodBg;
    if (score >= 40) return scoreAverageBg;
    if (score >= 20) return scoreBelowAvgBg;
    return scorePoorBg;
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

  // Dark Theme - Base colors (subtle blue tint)
  static const darkBackground = Color(0xFF0F1117);
  static const darkSurface = Color(0xFF1A1D27);
  static const darkBorder = Color(0xFF2A2D3A);
  static const darkAccent = Color(0xFF38BDF8);

  // Dark Theme - Text colors
  static const darkTextPrimary = Colors.white;
  static const darkTextSecondary = Color(0xBFFFFFFF);  // 75% white
  static const darkTextMuted = Color(0x8CFFFFFF);      // 55% white
  static const darkTextHint = Color(0x4DFFFFFF);       // 30% white
}
