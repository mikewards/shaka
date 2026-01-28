import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/animations.dart';
import '../../data/models/spot_models.dart';

/// Score breakdown card with Quiet Luxury styling.
/// 
/// Clean, text-only display with subtle progress indicators.
class ScoreBreakdownCard extends StatelessWidget {
  final ScoreBreakdown breakdown;

  const ScoreBreakdownCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          _ScoreRow(label: 'Visibility', score: breakdown.visibility),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Weather', score: breakdown.weather),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Swell', score: breakdown.swell),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Fish', score: breakdown.fishActivity),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Access', score: breakdown.accessibility),
          const SizedBox(height: 14),
          _ScoreRow(label: 'Safety', score: breakdown.safety),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;

  const _ScoreRow({
    required this.label,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getScoreColor(score);

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: AppAnimations.stateTransition,
              height: 4,
              child: LinearProgressIndicator(
                value: score / 100,
                backgroundColor: AppColors.border.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 28,
          child: Text(
            '$score',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
