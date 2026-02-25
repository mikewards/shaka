import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';
import '../utils/gibs_colormap.dart';

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
    source: 'Copernicus Marine (Satellite)',
    updateFrequency: 'Daily',
    description: 'Chlorophyll-a concentration measured by ocean color satellites. Lower chlorophyll means clearer water.',
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
};

/// Conditions card with clean row-based layout.
/// Each condition gets its own row for readability.
/// Tap row for info about data source.
class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;
  final GibsSatelliteReadings? satelliteReadings;

  // Dark theme colors
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  const ConditionsCard({super.key, required this.conditions, this.satelliteReadings});

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
            label: 'Swell',
            value: conditions.swell,
            sourceKey: 'swell',
          ),
          _ConditionRow(
            label: 'Wind',
            value: conditions.wind,
            sourceKey: 'wind',
          ),
          _ConditionRow(
            label: 'Water',
            value: conditions.waterTemp,
            sourceKey: 'water',
          ),
          _ConditionRow(
            label: 'Visibility',
            value: _resolveVisibility(),
            sourceKey: 'visibility',
            isLast: !(conditions.tideState.isNotEmpty && conditions.tideState != 'unknown'),
          ),
          if (conditions.tideState.isNotEmpty && conditions.tideState != 'unknown')
            _ConditionRow(
              label: 'Tide',
              value: conditions.tideState,
              sourceKey: 'tide',
              isLast: true,
            ),
        ],
      ),
    );
  }

  String _resolveVisibility() {
    if (conditions.visibility != 'No satellite data') return conditions.visibility;
    final readings = satelliteReadings;
    if (readings == null) return conditions.visibility;

    final hexColors = <String?>[
      readings.paceYesterdayColor ?? readings.paceTodayColor,
      readings.noaa20YesterdayColor ?? readings.noaa20TodayColor,
      readings.noaa21YesterdayColor ?? readings.noaa21TodayColor,
      readings.sentinel3aYesterdayColor ?? readings.sentinel3aTodayColor,
      readings.sentinel3bYesterdayColor ?? readings.sentinel3bTodayColor,
    ].whereType<String>().toList();

    if (hexColors.isEmpty) return conditions.visibility;

    final estimates = hexColors
        .map((hex) => estimateChlorophyllFromHex(hex))
        .whereType<double>()
        .toList();

    if (estimates.isEmpty) return conditions.visibility;

    final logSum = estimates.fold<double>(0, (s, v) => s + log(v));
    final chl = exp(logSum / estimates.length);

    final label = switch (chl) {
      < 0.1  => 'Crystal clear',
      < 0.3  => 'Blue water',
      < 0.5  => 'Slight haze',
      < 1.0  => 'Green tint',
      < 3.0  => 'Murky',
      < 5.0  => "Can't see your fins",
      < 10.0 => "Can't see your hand",
      _      => 'Zero vis',
    };
    return '$label (approx)';
  }

  void _showAllSourcesInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
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
                  const Expanded(
                    child: Text(
                      'Data Sources',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Condition data is aggregated from multiple scientific sources:',
                style: TextStyle(color: Colors.white54, fontSize: 13),
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
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.white38),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Data is refreshed automatically. Forecasts become more accurate as the date approaches.',
                        style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
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
      default: return key;
    }
  }

  Widget _buildSourceCard(BuildContext context, String label, _ConditionSource source) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  source.updateFrequency,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source.source,
            style: TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            source.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
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
    return Container(
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
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
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
    );
  }

}
