import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Score breakdown card with clean row-based layout.
/// Shows each scoring component with its weight and value.
class ScoreBreakdownCard extends StatelessWidget {
  final ScoreBreakdown breakdown;

  const ScoreBreakdownCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          _ScoreRow(
            label: 'Visibility',
            score: breakdown.visibility,
            weight: '25%',
          ),
          _ScoreRow(
            label: 'Weather',
            score: breakdown.weather,
            weight: '20%',
          ),
          _ScoreRow(
            label: 'Swell',
            score: breakdown.swell,
            weight: '20%',
          ),
          _ScoreRow(
            label: 'Fish Activity',
            score: breakdown.fishActivity,
            weight: '15%',
          ),
          _ScoreRow(
            label: 'Accessibility',
            score: breakdown.accessibility,
            weight: '10%',
          ),
          _ScoreRow(
            label: 'Safety',
            score: breakdown.safety,
            weight: '10%',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int score;
  final String weight;
  final bool isLast;

  const _ScoreRow({
    required this.label,
    required this.score,
    required this.weight,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: isLast ? 4 : 12,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppColors.border.withOpacity(0.2),
                ),
              ),
      ),
      child: Row(
        children: [
          // Label
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          // Progress bar
          Expanded(
            flex: 4,
            child: _ScoreBar(score: score),
          ),
          const SizedBox(width: 16),
          // Score value
          SizedBox(
            width: 32,
            child: Text(
              '$score',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.getScoreColor(score),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;

  const _ScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: score / 100,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.getScoreColor(score),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
