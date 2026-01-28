import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

class ScoreBreakdownCard extends StatelessWidget {
  final ScoreBreakdown breakdown;

  const ScoreBreakdownCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _ScoreRow(label: 'Visibility', score: breakdown.visibility, icon: Icons.visibility),
          const SizedBox(height: 12),
          _ScoreRow(label: 'Weather', score: breakdown.weather, icon: Icons.wb_sunny),
          const SizedBox(height: 12),
          _ScoreRow(label: 'Swell', score: breakdown.swell, icon: Icons.waves),
          const SizedBox(height: 12),
          _ScoreRow(label: 'Fish Activity', score: breakdown.fishActivity, icon: Icons.phishing),
          const SizedBox(height: 12),
          _ScoreRow(label: 'Accessibility', score: breakdown.accessibility, icon: Icons.directions_walk),
          const SizedBox(height: 12),
          _ScoreRow(label: 'Safety', score: breakdown.safety, icon: Icons.shield),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;
  final IconData icon;

  const _ScoreRow({
    required this.label,
    required this.score,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getScoreColor(score);

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 32,
          child: Text(
            '$score',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
