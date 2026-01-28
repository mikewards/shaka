import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';
import 'shaka_score_badge.dart';

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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _AccessBadge(access: spot.access),
                          const SizedBox(width: 8),
                          Text(
                            'Best: ${spot.bestTimeOfDay}',
                            style: Theme.of(context).textTheme.bodySmall,
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

            const SizedBox(height: 16),

            // Conditions Row
            Row(
              children: [
                _ConditionChip(
                  icon: Icons.visibility,
                  label: spot.conditions.visibility,
                ),
                const SizedBox(width: 8),
                _ConditionChip(
                  icon: Icons.water,
                  label: spot.conditions.swell,
                ),
                const SizedBox(width: 8),
                _ConditionChip(
                  icon: Icons.air,
                  label: spot.conditions.wind,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Fish Preview
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: spot.expectedFish.take(3).map((fish) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.sand,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    fish,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),

            // Risks (if any significant)
            if (spot.risks.isNotEmpty && spot.risks.first != 'No significant risks identified') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    spot.risks.first,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ],
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
    final isShore = access.toLowerCase() == 'shore';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.getAccessColor(access).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isShore ? Icons.beach_access : Icons.directions_boat,
            size: 12,
            color: AppColors.getAccessColor(access),
          ),
          const SizedBox(width: 4),
          Text(
            access.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.getAccessColor(access),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ConditionChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
