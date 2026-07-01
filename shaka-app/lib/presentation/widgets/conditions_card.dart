import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/unit_converter.dart';
import '../../data/models/spot_models.dart';
import '../../data/services/unit_preference_service.dart';
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
  'swell_corrected': _ConditionSource(
    source: 'Shaka Exposure Model',
    updateFrequency: 'Every 3 hours',
    description: 'Open-ocean swell scaled for coastline sheltering. Headlands, coves, and reefs can cut wave height 50%+ from the offshore reading.',
  ),
  'swell': _ConditionSource(
    source: 'Open-Meteo Marine + NDBC Buoys',
    updateFrequency: 'Hourly',
    description: 'Significant wave height in open water from NOAA WaveWatch III. Live NDBC buoy data is used when a buoy is within range.',
  ),
  'secondary_swell': _ConditionSource(
    source: 'Open-Meteo Marine API',
    updateFrequency: 'Hourly',
    description: 'Second wave system from a different direction. Also exposure-corrected when available. Can add energy or create cross-chop.',
  ),
  'wind': _ConditionSource(
    source: 'Open-Meteo Weather API (NOAA GFS)',
    updateFrequency: 'Hourly',
    description: '10-meter wind speed and direction. Offshore = clean conditions. Onshore = chop.',
  ),
  'water': _ConditionSource(
    source: 'Open-Meteo Marine API',
    updateFrequency: 'Hourly',
    description: 'Sea surface temperature from global ocean models.',
  ),
  'visibility': _ConditionSource(
    source: 'NASA & Copernicus Satellites',
    updateFrequency: 'Daily',
    description: 'Water clarity from satellite chlorophyll-a. Multi-satellite average (NASA PACE, NOAA-20/21, Sentinel-3). Low chlorophyll = blue water.',
  ),
  'tide': _ConditionSource(
    source: 'FES2022 Global Tide Model',
    updateFrequency: 'Predicted',
    description: 'Astronomical tide from 34 harmonic constituents. Drives current strength, bait movement, and feeding windows.',
  ),
  'depth': _ConditionSource(
    source: 'NOAA NCEI + GEBCO Bathymetry',
    updateFrequency: 'Static',
    description: 'Bottom depth from high-res NOAA coastal surveys where available, with GEBCO global grid as fallback.',
  ),
  'exposure': _ConditionSource(
    source: 'Shaka Coastal Analysis',
    updateFrequency: 'Computed once',
    description: 'How exposed or sheltered this spot is. Scans 16 compass bearings at 1\u20135 km to detect the open-ocean window.',
  ),
};

/// Conditions card with clean row-based layout.
/// Each condition gets its own row for readability.
/// Tap row for info about data source.
class ConditionsCard extends StatelessWidget {
  final SpotConditions conditions;
  final GibsSatelliteReadings? satelliteReadings;

  // Near-real-time wind, fetched by the detail screen after first paint. When
  // present it replaces the cached wind reading in the Wind row, with a visible
  // "Live" indicator; while [liveWindLoading] is true the row shows a subtle
  // "checking..." cue so the value never appears to change silently.
  final double? liveWindSpeedKts;
  final String? liveWindDirectionCardinal;
  final int? liveWindRetrievedAt;
  final bool liveWindLoading;

  // Dark theme colors
  static const _cardColor = AppColors.darkSurface;
  static const _borderColor = AppColors.darkBorder;

  const ConditionsCard({
    super.key,
    required this.conditions,
    this.satelliteReadings,
    this.liveWindSpeedKts,
    this.liveWindDirectionCardinal,
    this.liveWindRetrievedAt,
    this.liveWindLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final units = UnitPreferenceService();
    return ListenableBuilder(
      listenable: units,
      builder: (context, _) {
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
                          style: TextStyle(color: AppColors.darkTextHint, fontSize: 11),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.info_outline, size: 12, color: AppColors.darkTextHint),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ConditionRow(
                label: 'Swell',
                value: conditions.swellHeightFt != null
                    ? UnitConverter.formatSwell(conditions.swellHeightFt, conditions.swellPeriodSec, conditions.swellDirection, units.system)
                    : (conditions.swellCorrected ?? conditions.swell),
                sourceKey: conditions.swellCorrected != null ? 'swell_corrected' : 'swell',
              ),
              _buildWindRow(units),
              _ConditionRow(
                label: 'Water',
                value: conditions.waterTempC != null
                    ? UnitConverter.formatTemperature(conditions.waterTempC, units.system)
                    : conditions.waterTemp,
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
                  value: UnitConverter.formatDepth(conditions.bathymetryDepthM, units.system),
                  sourceKey: 'depth',
                  isLast: true,
                ),
            ],
          ),
        );
      },
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

  /// Build the Wind row, preferring the near-real-time live reading when it has
  /// arrived. Never swaps the value silently: shows a "checking..." cue while
  /// the live fetch is in flight and a "Live" indicator (with a brief highlight)
  /// once it resolves.
  Widget _buildWindRow(UnitPreferenceService units) {
    final cachedValue = conditions.windSpeedKts != null
        ? UnitConverter.formatWind(conditions.windSpeedKts, conditions.windDirectionCardinal, units.system)
        : conditions.wind;
    final hasLive = liveWindSpeedKts != null;
    final effectiveValue = hasLive
        ? UnitConverter.formatWind(liveWindSpeedKts, liveWindDirectionCardinal, units.system)
        : cachedValue;
    return _WindConditionRow(
      value: effectiveValue,
      loading: liveWindLoading && !hasLive,
      showLive: hasLive,
      highlightOnChange: hasLive && effectiveValue != cachedValue,
      liveRetrievedAt: liveWindRetrievedAt,
    );
  }

  void _showAllSourcesInfo(BuildContext context) {
    // Only show sources for rows visible in the CONDITIONS card, in display order
    final visibleKeys = <String>[
      conditions.swellCorrected != null ? 'swell_corrected' : 'swell',
      'wind',
      'water',
      'visibility',
      if (conditions.tideState.isNotEmpty && conditions.tideState != 'unknown') 'tide',
      if (conditions.bathymetryDepthM != null) 'depth',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
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
                    icon: const Icon(Icons.close, color: AppColors.darkTextMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Condition data is aggregated from multiple scientific sources:',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ...visibleKeys
                  .where((k) => _conditionSources.containsKey(k))
                  .map((k) => _buildSourceCard(
                    context,
                    _labelForKey(k),
                    _conditionSources[k]!,
                    retrievedAt: _retrievedAtForKey(k),
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
                    Icon(Icons.schedule, size: 16, color: AppColors.darkTextHint),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Data is refreshed automatically. Forecasts become more accurate as the date approaches.',
                        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12, height: 1.4),
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

  /// Actual retrieval time (epoch millis) for swell/wind keys, else null.
  int? _retrievedAtForKey(String key) {
    switch (key) {
      case 'swell':
      case 'swell_corrected':
      case 'secondary_swell':
        return conditions.swellRetrievedAt;
      case 'wind':
        return conditions.windRetrievedAt;
      default:
        return null;
    }
  }

  /// Human-readable "Retrieved ..." badge from an epoch-millis timestamp.
  String _formatRetrieved(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    final now = DateTime.now();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final time = '$hour12:$minute $ampm';
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) return 'Retrieved $time';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Retrieved ${months[dt.month - 1]} ${dt.day}, $time';
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

  Widget _buildSourceCard(BuildContext context, String label, _ConditionSource source, {int? retrievedAt}) {
    final badge = retrievedAt != null ? _formatRetrieved(retrievedAt) : source.updateFrequency;
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
                  badge,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
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
              color: AppColors.darkTextSecondary,
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
            style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
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

/// Wind row variant that surfaces the near-real-time refresh state: a subtle
/// "checking latest..." cue while fetching, and a brief highlight plus a "Live"
/// timestamp when the value updates in place -- so the reading never changes
/// silently under the user.
class _WindConditionRow extends StatefulWidget {
  final String value;
  final bool loading;
  final bool showLive;
  final bool highlightOnChange;
  final int? liveRetrievedAt;

  const _WindConditionRow({
    required this.value,
    required this.loading,
    required this.showLive,
    required this.highlightOnChange,
    this.liveRetrievedAt,
  });

  @override
  State<_WindConditionRow> createState() => _WindConditionRowState();
}

class _WindConditionRowState extends State<_WindConditionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1.0, // start settled: no flash on first mount
    );
    if (widget.highlightOnChange) _flash.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _WindConditionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flash only when the displayed value actually changes to a live reading.
    if (widget.highlightOnChange && widget.value != oldWidget.value) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  String _relativeTime(int epochMs) {
    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
    final mins = diff.inMinutes;
    if (mins <= 0) return 'just now';
    if (mins == 1) return '1m ago';
    if (mins < 60) return '${mins}m ago';
    final hrs = diff.inHours;
    return hrs == 1 ? '1h ago' : '${hrs}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Wind',
            style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _flash,
                  builder: (context, child) {
                    final t = 1.0 - _flash.value; // 1 right after change -> 0
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.18 * t),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: child,
                    );
                  },
                  child: Text(
                    widget.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(height: 3),
                _buildIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator() {
    if (widget.loading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 9,
            height: 9,
            child: CircularProgressIndicator(
              strokeWidth: 1.4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.darkTextHint),
            ),
          ),
          SizedBox(width: 5),
          Text(
            'checking latest\u2026',
            style: TextStyle(color: AppColors.darkTextHint, fontSize: 10),
          ),
        ],
      );
    }
    if (widget.showLive) {
      final when = widget.liveRetrievedAt != null
          ? _relativeTime(widget.liveRetrievedAt!)
          : 'just now';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Live \u00b7 $when',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
