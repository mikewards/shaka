import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum ShakaScoreSize { small, medium, large }

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
    double labelSize;

    switch (size) {
      case ShakaScoreSize.small:
        badgeSize = 40;
        fontSize = 16;
        labelSize = 8;
        break;
      case ShakaScoreSize.medium:
        badgeSize = 56;
        fontSize = 20;
        labelSize = 9;
        break;
      case ShakaScoreSize.large:
        badgeSize = 72;
        fontSize = 28;
        labelSize = 10;
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: badgeSize,
          height: badgeSize,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$confidence% conf',
          style: TextStyle(
            fontSize: labelSize,
            color: AppColors.textMuted,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}
