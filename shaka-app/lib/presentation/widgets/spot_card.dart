import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/animations.dart';
import '../../data/models/spot_models.dart';
import 'shaka_score_badge.dart';

/// Spot card with Quiet Luxury styling.
/// 
/// - 14dp corner radius (soft but not bubbly)
/// - Subtle border
/// - Text-based navigation indicator
class SpotCard extends StatelessWidget {
  final SpotSummary spot;
  final VoidCallback onTap;

  const SpotCard({
    super.key,
    required this.spot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.stateTransition,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spot.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _AccessBadge(access: spot.access),
                          const SizedBox(width: 12),
                          Text(
                            spot.bestTimeOfDay,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ShakaScoreBadge(
                  score: spot.shakaScore,
                  confidence: spot.confidence,
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Conditions Row - Text only, no icons
            Row(
              children: [
                _ConditionChip(label: spot.conditions.visibility),
                const SizedBox(width: 10),
                _ConditionChip(label: spot.conditions.swell),
                const SizedBox(width: 10),
                _ConditionChip(label: spot.conditions.wind),
              ],
            ),

            const SizedBox(height: 14),

            // Fish Preview
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: spot.expectedFish.take(3).map((fish) {
                return Text(
                  fish,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // View indicator - text chevron
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'View',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '>',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  final String access;

  const _AccessBadge({required this.access});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.getAccessColor(access).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        access.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.getAccessColor(access),
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final String label;

  const _ConditionChip({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
