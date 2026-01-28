import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Conditions card with Quiet Luxury styling.
/// 
/// Text-only display, no icons - let the data speak.
class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;

  const ConditionsCard({super.key, required this.conditions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ConditionItem(
              label: 'VISIBILITY',
              value: conditions.visibility,
            ),
          ),
          Expanded(
            child: _ConditionItem(
              label: 'WATER',
              value: conditions.waterTemp,
            ),
          ),
          Expanded(
            child: _ConditionItem(
              label: 'SWELL',
              value: conditions.swell,
            ),
          ),
          Expanded(
            child: _ConditionItem(
              label: 'WIND',
              value: conditions.wind,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionItem extends StatelessWidget {
  final String label;
  final String value;

  const _ConditionItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
