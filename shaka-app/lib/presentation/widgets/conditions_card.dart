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
    source: 'Open-Meteo Marine + NDBC Buoys',
    updateFrequency: 'Hourly',
    description: 'Open-ocean significant wave height from NOAA wave models. When an NDBC buoy is nearby, real-time buoy readings are used instead for higher accuracy.',
  ),
  'swell_corrected': _ConditionSource(
    source: 'Exposure-attenuated swell model',
    updateFrequency: 'Every 3 hours',
    description: 'Open-ocean swell adjusted for this spot\'s coastal exposure. Accounts for headlands, coves, and shoreline orientation so sheltered spots show reduced wave heights.',
  ),
  'secondary_swell': _ConditionSource(
    source: 'Open-Meteo Marine API',
    updateFrequency: 'Hourly',
    description: 'Secondary swell system traveling from a different direction than the primary swell. Also corrected for this spot\'s exposure when available.',
  ),
  'wind': _ConditionSource(
    source: 'Open-Meteo Weather API',
    updateFrequency: 'Hourly',
    description: 'Surface wind speed and direction. High winds create surface chop and reduce visibility.',
  ),
  'tide': _ConditionSource(
    source: 'FES2022 Global Tide Model',
    updateFrequency: 'Predicted',
    description: 'Astronomical tide predictions from the FES2022 global ocean model. Tidal movement affects current strength and fish activity.',
  ),
  'exposure': _ConditionSource(
    source: 'Multi-ring land/water analysis',
    updateFrequency: 'Computed once',
    description: 'Which direction this spot faces the open ocean and how wide the exposure arc is. Sampled at 1km, 2km, and 5km across 16 compass directions to detect sheltering headlands and coves.',
  ),
  'depth': _ConditionSource(
    source: 'NOAA NCEI DEM + GEBCO',
    updateFrequency: 'Computed once',
    description: 'Seafloor depth at this spot from high-resolution NOAA bathymetry surveys with global GEBCO data as fallback.',
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
            value: conditions.swellCorrected ?? conditions.swell,
            sourceKey: conditions.swellCorrected != null ? 'swell_corrected' : 'swell',
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
            isLast: !(conditions.tideState.isNotEmpty && conditions.tideState != 'unknown') && conditions.bathymetryDepthM == null,
          ),
          if (conditions.tideState.isNotEmpty && conditions.tideState != 'unknown')
            _ConditionRow(
              label: 'Tide',
              value: conditions.tideState,
              sourceKey: 'tide',
              isLast: conditions.bathymetryDepthM == null,
            ),
          if (conditions.bathymetryDepthM != null)
            _ConditionRow(
              label: 'Depth',
              value: '${conditions.bathymetryDepthM!.toStringAsFixed(1)}m / ${(conditions.bathymetryDepthM! * 3.28084).toStringAsFixed(0)}ft',
              sourceKey: 'depth',
              isLast: true,
            ),
        ],
      ),
    );
  }

  static String _bearingToCardinal(int degrees) {
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                   'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    return dirs[((degrees % 360) / 22.5).round() % 16];
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
    return label;
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
      case 'swell': return 'Swell (Open Ocean)';
      case 'swell_corrected': return 'Swell (At Spot)';
      case 'secondary_swell': return 'Secondary Swell';
      case 'wind': return 'Wind';
      case 'tide': return 'Tide';
      case 'exposure': return 'Exposure';
      case 'depth': return 'Depth';
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
