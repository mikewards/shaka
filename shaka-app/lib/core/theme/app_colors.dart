import 'package:flutter/material.dart';

/// Shaka Color Palette
/// 
/// Design: "Early Square meets The Old Man and the Sea"
/// - Deep ocean blues for trust and depth
/// - Warm sand tones for approachability
/// - Coral accent for energy and action
class AppColors {
  AppColors._();

  // Primary - Deep Ocean Blue
  static const Color oceanBlue = Color(0xFF1A365D);
  static const Color oceanBlueLight = Color(0xFF2C5282);
  static const Color oceanBlueDark = Color(0xFF0F2942);

  // Secondary - Coral (action color)
  static const Color coral = Color(0xFFE07A5F);
  static const Color coralLight = Color(0xFFE8998D);
  static const Color coralDark = Color(0xFFC65D3D);

  // Neutral - Sand tones
  static const Color sand = Color(0xFFF5E6D3);
  static const Color sandLight = Color(0xFFFAF5EE);
  static const Color sandDark = Color(0xFFE8D4BC);

  // Background & Surface
  static const Color background = Color(0xFFFCFAF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5C5C5C);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color textOnDark = Color(0xFFFAFAFA);

  // Borders
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);
  static const Color borderDark = Color(0xFFD1D5DB);

  // Shaka Score Colors
  static const Color scoreExcellent = Color(0xFF059669);  // 80-100
  static const Color scoreGood = Color(0xFF10B981);       // 60-79
  static const Color scoreFair = Color(0xFFF59E0B);       // 40-59
  static const Color scorePoor = Color(0xFFEF4444);       // 0-39

  // Status
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF3B82F6);

  // Semantic - Access Types
  static const Color shoreDive = Color(0xFF10B981);
  static const Color boatDive = Color(0xFF3B82F6);

  /// Get score color based on shaka score value
  static Color getScoreColor(int score) {
    if (score >= 80) return scoreExcellent;
    if (score >= 60) return scoreGood;
    if (score >= 40) return scoreFair;
    return scorePoor;
  }

  /// Get access type color
  static Color getAccessColor(String access) {
    return access.toLowerCase() == 'shore' ? shoreDive : boatDive;
  }
}
