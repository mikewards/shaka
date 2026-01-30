import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Data source information for conditions
class _ConditionSource {
  final String source;
  final String updateFrequency;
  final String description;

  const _ConditionSource({
    required this.source,
    required this.updateFrequency,
    required this.description,
  });
}

const _conditionSources = {
  'visibility': _ConditionSource(
    source: 'NOAA CoastWatch (VIIRS Satellite)',
    updateFrequency: 'Daily',
    description: 'Estimated from chlorophyll-a concentration and sea surface temperature. Clear water has low chlorophyll levels.',
  ),
  'water': _ConditionSource(
    source: 'Open-Meteo Marine API',
    updateFrequency: 'Hourly',
    description: 'Sea surface temperature from ocean weather models. Affects fish behavior and wetsuit requirements.',
  ),
  'swell': _ConditionSource(
    source: 'Open-Meteo Marine API',
    updateFrequency: 'Hourly',
    description: 'Wave height and period from NOAA wave models. Affects underwater visibility and entry/exit safety.',
  ),
  'wind': _ConditionSource(
    source: 'Open-Meteo Weather API',
    updateFrequency: 'Hourly',
    description: 'Surface wind speed and direction. High winds create surface chop and reduce visibility.',
  ),
  'tide': _ConditionSource(
    source: 'NOAA CO-OPS Tide Stations',
    updateFrequency: 'Predicted',
    description: 'Tide predictions for nearby stations. Tidal movement affects current strength and fish activity.',
  ),
  'current': _ConditionSource(
    source: 'NOAA CO-OPS Current Stations',
    updateFrequency: 'Real-time / Predicted',
    description: 'Current speed and direction. Strong currents affect dive safety and require more experience.',
  ),
};

/// Conditions card with clean row-based layout.
/// Each condition gets its own row for readability.
/// Tap row for info about data source.
class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;

  // Dark theme colors
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  const ConditionsCard({super.key, required this.conditions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with info hint
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Conditions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showAllSourcesInfo(context);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Data sources',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 12, color: Colors.white38),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ConditionRow(
            label: 'Visibility',
            value: conditions.visibility,
            sourceKey: 'visibility',
          ),
          _ConditionRow(
            label: 'Water',
            value: conditions.waterTemp,
            sourceKey: 'water',
          ),
          _ConditionRow(
            label: 'Swell',
            value: conditions.swell,
            sourceKey: 'swell',
          ),
          _ConditionRow(
            label: 'Wind',
            value: conditions.wind,
            sourceKey: 'wind',
          ),
          if (conditions.tideState.isNotEmpty && conditions.tideState != 'unknown')
            _ConditionRow(
              label: 'Tide',
              value: conditions.tideState,
              sourceKey: 'tide',
            ),
          if (conditions.currentStrength.isNotEmpty && 
              !conditions.currentStrength.contains('N/A'))
            _ConditionRow(
              label: 'Current',
              value: conditions.currentStrength,
              sourceKey: 'current',
              isLast: true,
            ),
        ],
      ),
    );
  }

  void _showAllSourcesInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Data Sources',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Condition data is aggregated from multiple scientific sources:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              ..._conditionSources.entries.map((e) => _buildSourceCard(
                context,
                _labelForKey(e.key),
                e.value,
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Data is refreshed automatically. Forecasts become more accurate as the date approaches.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelForKey(String key) {
    switch (key) {
      case 'visibility': return 'Visibility';
      case 'water': return 'Water Temperature';
      case 'swell': return 'Swell';
      case 'wind': return 'Wind';
      case 'tide': return 'Tide';
      case 'current': return 'Current';
      default: return key;
    }
  }

  Widget _buildSourceCard(BuildContext context, String label, _ConditionSource source) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.oceanBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  source.updateFrequency,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.oceanBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source.source,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.oceanBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            source.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  final String label;
  final String value;
  final String sourceKey;
  final bool isLast;

  const _ConditionRow({
    required this.label,
    required this.value,
    required this.sourceKey,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showSourceInfo(context);
      },
      child: Container(
        padding: EdgeInsets.only(
          top: 10,
          bottom: isLast ? 4 : 10,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: Colors.white10),
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.info_outline, size: 10, color: Colors.white24),
              ],
            ),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSourceInfo(BuildContext context) {
    final source = _conditionSources[sourceKey];
    if (source == null) return;

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
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(context, 'Source', source.source),
            _buildInfoRow(context, 'Updates', source.updateFrequency),
            const SizedBox(height: 12),
            Text(
              source.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    'Current value: ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
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

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.oceanBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
