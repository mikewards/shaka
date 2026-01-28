import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Conditions card with clean row-based layout.
/// Each condition gets its own row for readability.
class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;

  const ConditionsCard({super.key, required this.conditions});

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
          _ConditionRow(label: 'Visibility', value: conditions.visibility),
          _ConditionRow(label: 'Water', value: conditions.waterTemp),
          _ConditionRow(label: 'Swell', value: conditions.swell),
          _ConditionRow(label: 'Wind', value: conditions.wind),
          if (conditions.tideState.isNotEmpty && conditions.tideState != 'unknown')
            _ConditionRow(label: 'Tide', value: conditions.tideState),
          if (conditions.currentStrength.isNotEmpty && 
              !conditions.currentStrength.contains('N/A'))
            _ConditionRow(
              label: 'Current',
              value: conditions.currentStrength,
              isLast: true,
            ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _ConditionRow({
    required this.label,
    required this.value,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
