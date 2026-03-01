import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/animations.dart';
import '../../data/models/spot_models.dart';
import 'shaka_score_badge.dart';

/// Spot card with clean, Square-inspired styling.
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name + Score
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
                      Text(
                        spot.bestTimeOfDay,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
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

            const SizedBox(height: 20),

            // Conditions as clean rows
            _ConditionSummary(conditions: spot.conditions),

            const SizedBox(height: 16),

            // Fish preview + View indicator
            Row(
              children: [
                Expanded(
                  child: Text(
                    spot.expectedFish.take(3).join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'View >',
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

/// Compact condition summary for spot cards
class _ConditionSummary extends StatelessWidget {
  final SpotConditions conditions;

  const _ConditionSummary({required this.conditions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniCondition(
              label: 'Vis',
              value: _extractValue(conditions.visibility),
            ),
          ),
          _Divider(),
          Expanded(
            child: _MiniCondition(
              label: 'Temp',
              value: _extractTemp(conditions.waterTemp),
            ),
          ),
          _Divider(),
          Expanded(
            child: _MiniCondition(
              label: 'Swell',
              value: _extractSwell(conditions.swell),
            ),
          ),
          _Divider(),
          Expanded(
            child: _MiniCondition(
              label: 'Wind',
              value: _extractWind(conditions.wind),
            ),
          ),
        ],
      ),
    );
  }

  String _extractValue(String vis) {
    // Extract just the meters value: "45m (exceptional)" -> "45m"
    final match = RegExp(r'(\d+m)').firstMatch(vis);
    return match?.group(1) ?? 'N/A';
  }

  String _extractTemp(String temp) {
    // Extract Fahrenheit: "24°C / 75°F" -> "75°F"
    final match = RegExp(r'(\d+°F)').firstMatch(temp);
    return match?.group(1) ?? 'N/A';
  }

  String _extractSwell(String swell) {
    final corrected = conditions.swellCorrected;
    final source = corrected ?? swell;
    final match = RegExp(r'([\d-]+ft)').firstMatch(source);
    return match?.group(1) ?? 'N/A';
  }

  String _extractWind(String wind) {
    // Extract just the knots: "12 kts NW" -> "12 kts"
    final match = RegExp(r'(\d+\s*kts|\d+\s*knots)').firstMatch(wind);
    return match?.group(1) ?? 'N/A';
  }
}

class _MiniCondition extends StatelessWidget {
  final String label;
  final String value;

  const _MiniCondition({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: AppColors.border.withOpacity(0.3),
    );
  }
}

