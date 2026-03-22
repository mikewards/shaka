import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/services/unit_preference_service.dart';
import 'score_tier_pill.dart';

enum ShakaScoreSize { small, medium, large }

/// Score badge with Quiet Luxury styling.
/// 
/// Uses desaturated colors and lighter font weights.
/// Tappable to show explanation of how the score is calculated.
class ShakaScoreBadge extends StatelessWidget {
  final int score;
  final int confidence;
  final ShakaScoreSize size;
  final bool showLabel;
  final bool interactive;

  const ShakaScoreBadge({
    super.key,
    required this.score,
    required this.confidence,
    this.size = ShakaScoreSize.medium,
    this.showLabel = false,
    this.interactive = true,
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

    final badge = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScoreTierPill(score: score, width: badgeSize * 0.85, height: 10),
        if (showLabel) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Shaka Score',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (interactive) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              ],
            ],
          ),
        ],
      ],
    );

    if (!interactive) return badge;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showScoreExplanation(context);
      },
      child: badge,
    );
  }

  void _showScoreExplanation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.oceanBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('🤙', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shaka Score',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Overall diving conditions',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'The Shaka Score (0-100) combines multiple factors to rate spearfishing conditions:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildFactorRow(context, 'Visibility', '35%', 'Chlorophyll concentration (satellite data)'),
            _buildFactorRow(context, 'Swell', '28%', 'Wave height (${UnitConverter.swellHeightUnit(UnitPreferenceService().system)})'),
            _buildFactorRow(context, 'Wind', '22%', 'Wind speed (${UnitConverter.windSpeedUnit(UnitPreferenceService().system)})'),
            _buildFactorRow(context, 'Solunar', '15%', 'Moon transit & feeding periods'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confidence: $confidence% (based on forecast accuracy)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFactorRow(BuildContext context, String label, String weight, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              weight,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.oceanBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  desc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
