import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum ShakaScoreSize { small, medium, large }

/// Score badge with Quiet Luxury styling.
/// 
/// Uses desaturated colors and lighter font weights.
class ShakaScoreBadge extends StatelessWidget {
  final int score;
  final int confidence;
  final ShakaScoreSize size;

  const ShakaScoreBadge({
    super.key,
    required this.score,
    required this.confidence,
    this.size = ShakaScoreSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getScoreColor(score);
    
    double badgeSize;
    double fontSize;

    switch (size) {
      case ShakaScoreSize.small:
        badgeSize = 42;
        fontSize = 16;
        break;
      case ShakaScoreSize.medium:
        badgeSize = 56;
        fontSize = 20;
        break;
      case ShakaScoreSize.large:
        badgeSize = 70;
        fontSize = 26;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: badgeSize,
          height: badgeSize,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          ),
          child: Center(
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                color: color,
                fontFamily: 'Inter',
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
