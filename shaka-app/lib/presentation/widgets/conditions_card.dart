import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;

  const ConditionsCard({super.key, required this.conditions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ConditionItem(
              icon: Icons.visibility,
              label: 'Visibility',
              value: conditions.visibility,
            ),
          ),
          _Divider(),
          Expanded(
            child: _ConditionItem(
              icon: Icons.thermostat,
              label: 'Water',
              value: conditions.waterTemp,
            ),
          ),
          _Divider(),
          Expanded(
            child: _ConditionItem(
              icon: Icons.waves,
              label: 'Swell',
              value: conditions.swell,
            ),
          ),
          _Divider(),
          Expanded(
            child: _ConditionItem(
              icon: Icons.air,
              label: 'Wind',
              value: conditions.wind,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ConditionItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.oceanBlue, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
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
      height: 40,
      color: AppColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
