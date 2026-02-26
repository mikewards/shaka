import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';
import '../utils/gibs_colormap.dart';

/// Visibility label derived from chlorophyll-a concentration.
/// Matches the backend SpotService thresholds exactly.
class _VisibilityInfo {
  final String label;
  final Color color;
  final String description;
  final String range;

  const _VisibilityInfo({
    required this.label,
    required this.color,
    required this.description,
    required this.range,
  });
}

_VisibilityInfo _getVisibilityInfo(double? chl) {
  if (chl == null) {
    return const _VisibilityInfo(
      label: 'No data',
      color: Colors.grey,
      description: 'Satellite data not yet available for this spot.',
      range: '--',
    );
  }
  if (chl < 0.1) {
    return _VisibilityInfo(
      label: 'Crystal clear',
      color: const Color(0xFF4400AA),
      description: 'Open ocean clarity. Exceptional visibility for diving.',
      range: '< 0.1 mg/m³',
    );
  }
  if (chl < 0.3) {
    return _VisibilityInfo(
      label: 'Blue water',
      color: const Color(0xFF0066FF),
      description: 'Very good conditions. Great visibility underwater.',
      range: '0.1 – 0.3 mg/m³',
    );
  }
  if (chl < 0.5) {
    return _VisibilityInfo(
      label: 'Slight haze',
      color: const Color(0xFF00CCAA),
      description: 'Typical coastal conditions. Visibility slightly reduced.',
      range: '0.3 – 0.5 mg/m³',
    );
  }
  if (chl < 1.0) {
    return _VisibilityInfo(
      label: 'Green tint',
      color: const Color(0xFFAADD00),
      description: 'Water shifting from blue to green. Reduced clarity.',
      range: '0.5 – 1.0 mg/m³',
    );
  }
  if (chl < 3.0) {
    return _VisibilityInfo(
      label: 'Murky',
      color: const Color(0xFFFFCC00),
      description: 'Significant phytoplankton. Limited visibility.',
      range: '1.0 – 3.0 mg/m³',
    );
  }
  if (chl < 5.0) {
    return _VisibilityInfo(
      label: "Can't see your fins",
      color: const Color(0xFFFF8800),
      description: 'Very poor visibility. Not recommended for spearfishing.',
      range: '3.0 – 5.0 mg/m³',
    );
  }
  if (chl < 10.0) {
    return _VisibilityInfo(
      label: "Can't see your hand",
      color: const Color(0xFFFF4400),
      description: 'Dense bloom. Dangerous conditions.',
      range: '5.0 – 10.0 mg/m³',
    );
  }
  return _VisibilityInfo(
    label: 'Zero vis',
    color: const Color(0xFF880000),
    description: 'Severe bloom. No underwater visibility.',
    range: '> 10.0 mg/m³',
  );
}

/// Card displaying satellite-based visibility data.
///
/// COLLAPSED: Shows the visibility label (e.g., "Clear") with a color indicator.
/// EXPANDED: Shows measured chlorophyll, satellite imagery colors, and legend.
/// INFO: Tapping the "?" shows what each label means.
class SatelliteReadingsCard extends StatefulWidget {
  final GibsSatelliteReadings? readings;
  final int? visibilityScore;

  const SatelliteReadingsCard({super.key, this.readings, this.visibilityScore});

  @override
  State<SatelliteReadingsCard> createState() => _SatelliteReadingsCardState();
}

class _SatelliteReadingsCardState extends State<SatelliteReadingsCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // Dark theme colors (matching ConditionsCard)
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  // Chlorophyll legend colors (matching GIBS layer)
  static const _legendColors = [
    Color(0xFF4400AA),
    Color(0xFF0044FF),
    Color(0xFF00AAFF),
    Color(0xFF00FFAA),
    Color(0xFF00FF00),
    Color(0xFFAAFF00),
    Color(0xFFFFFF00),
    Color(0xFFFFAA00),
    Color(0xFFFF4400),
    Color(0xFF880000),
  ];

  @override
  Widget build(BuildContext context) {
    final readings = widget.readings;
    if (readings == null || !readings.hasAnyData) {
      return const SizedBox.shrink();
    }

    // Use Copernicus L3 chlorophyll if available; otherwise estimate from GIBS colors
    double? effectiveChl = readings.noaaErddapChlorophyll;
    bool isEstimated = false;
    if (effectiveChl == null) {
      effectiveChl = _estimateFromSatelliteColors(readings);
      isEstimated = effectiveChl != null;
    }

    var info = _getVisibilityInfo(effectiveChl);

    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          // --- Collapsed header (always visible) ---
          _buildHeader(info, readings),

          // --- Expanded details ---
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _buildExpandedContent(readings, info),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  /// The always-visible header row: label, color dot, chevron.
  Widget _buildHeader(_VisibilityInfo info, GibsSatelliteReadings readings) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _expanded = !_expanded);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Color indicator dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: info.color,
                border: Border.all(color: Colors.white24, width: 0.5),
              ),
            ),
            const SizedBox(width: 10),
            // The actual label (e.g., "Clear")
            Expanded(
              child: Text(
                info.label,
                style: TextStyle(
                  color: info.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Expand chevron
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full expanded content: measured chlorophyll, legend, satellite imagery.
  Widget _buildExpandedContent(
      GibsSatelliteReadings readings, _VisibilityInfo info) {
    final estimatedChl = readings.noaaErddapChlorophyll == null
        ? _estimateFromSatelliteColors(readings)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Divider
          Container(height: 1, color: Colors.white10),
          const SizedBox(height: 14),

          // Visibility scale
          _buildVisibilityScale(readings, estimatedChl),
          const SizedBox(height: 16),

          // Copernicus Marine value
          _buildCopernicusSection(readings),
          const SizedBox(height: 16),

          // Satellite imagery
          _buildSatelliteImagerySection(readings),
        ],
      ),
    );
  }

  /// Measured chlorophyll (Copernicus Marine L3 NRT) — compact version.
  Widget _buildMeasuredChlorophyllSection(
      GibsSatelliteReadings readings, _VisibilityInfo info) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MULTI-SATELLITE CHLOROPHYLL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'L3 QC',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                readings.noaaErddapChlorophyll!.toStringAsFixed(3),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'mg/m\u00B3',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              if (readings.noaaErddapFetchTime != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _formatDateTime(readings.noaaErddapFetchTime!),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Source: Copernicus Marine Service',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Estimated chlorophyll from satellite imagery colors.
  Widget _buildEstimatedChlorophyllSection(double estimatedChl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BLENDED SATELLITE ESTIMATE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'APPROX',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                estimatedChl.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'mg/m\u00B3',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Source: Blended satellite estimate',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Copernicus Marine chlorophyll value — always shown, with "Not available" fallback.
  Widget _buildCopernicusSection(GibsSatelliteReadings readings) {
    final chl = readings.noaaErddapChlorophyll;
    final available = chl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'COPERNICUS MARINE VALUE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '#1 PREFERRED',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        () {
          final highlight = available;
          final highlightColor = highlight
              ? _getVisibilityInfo(chl).color
              : Colors.transparent;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: highlight
                  ? highlightColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: highlight
                  ? Border.all(color: highlightColor.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              children: [
                Text(
                  'Copernicus',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                if (available) ...[
                  Text(
                    '${chl.toStringAsFixed(3)} mg/m\u00B3',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                  ),
                  Expanded(
                    child: Text(
                      readings.noaaErddapFetchTime != null
                          ? _formatDateTime(readings.noaaErddapFetchTime!)
                          : '',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'Not available',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
              ],
            ),
          );
        }(),
      ],
    );
  }

  /// Compute geometric mean of satellite-derived chlorophyll estimates.
  double? _estimateFromSatelliteColors(GibsSatelliteReadings readings) {
    final hexColors = <String?>[
      readings.paceYesterdayColor ?? readings.paceTodayColor,
      readings.noaa20YesterdayColor ?? readings.noaa20TodayColor,
      readings.noaa21YesterdayColor ?? readings.noaa21TodayColor,
      readings.sentinel3aYesterdayColor ?? readings.sentinel3aTodayColor,
      readings.sentinel3bYesterdayColor ?? readings.sentinel3bTodayColor,
    ].whereType<String>().toList();

    if (hexColors.isEmpty) return null;

    final estimates = hexColors
        .map((hex) => estimateChlorophyllFromHex(hex))
        .whereType<double>()
        .toList();

    if (estimates.isEmpty) return null;

    // Geometric mean (average in log space) for log-distributed data
    final logSum = estimates.fold<double>(0, (s, v) => s + log(v));
    return exp(logSum / estimates.length);
  }

  /// Chlorophyll color legend bar.
  Widget _buildVisibilityScale(GibsSatelliteReadings readings, double? estimatedChl) {
    const labels = [
      ('Crystal clear', '< 0.1', Color(0xFF4400AA)),
      ('Blue water', '0.1 – 0.3', Color(0xFF0066FF)),
      ('Slight haze', '0.3 – 0.5', Color(0xFF00CCAA)),
      ('Green tint', '0.5 – 1.0', Color(0xFFAADD00)),
      ('Murky', '1.0 – 3.0', Color(0xFFFFCC00)),
      ("Can't see your fins", '3.0 – 5.0', Color(0xFFFF8800)),
      ("Can't see your hand", '5.0 – 10.0', Color(0xFFFF4400)),
      ('Zero vis', '> 10.0', Color(0xFF880000)),
    ];

    final effectiveChl = readings.noaaErddapChlorophyll ?? estimatedChl;
    final currentLabel = _getVisibilityInfo(effectiveChl).label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'VISIBILITY SCALE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showSatelliteInfo(context);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.white54),
                    SizedBox(width: 4),
                    Text(
                      'About',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...labels.map((entry) {
          final (label, range, color) = entry;
          final isCurrent = label == currentLabel;
          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isCurrent
                  ? color.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isCurrent
                  ? Border.all(color: color.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  range,
                  style: TextStyle(
                    color: isCurrent ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Satellite imagery section (PACE, NOAA-20, etc.)
  Widget _buildSatelliteImagerySection(GibsSatelliteReadings readings) {
    final hasSatelliteColors = readings.paceTodayColor != null ||
        readings.paceYesterdayColor != null ||
        readings.noaa20TodayColor != null ||
        readings.noaa20YesterdayColor != null ||
        readings.noaa21TodayColor != null ||
        readings.noaa21YesterdayColor != null ||
        readings.sentinel3aTodayColor != null ||
        readings.sentinel3aYesterdayColor != null ||
        readings.sentinel3bTodayColor != null ||
        readings.sentinel3bYesterdayColor != null;

    if (!hasSatelliteColors) return const SizedBox.shrink();

    const showEstimates = true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'NASA GIBS SATELLITE VALUES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '#2 FALLBACK',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBlendedEstimateRow(readings, highlight: readings.noaaErddapChlorophyll == null),
        _buildSatelliteColorRow(
          name: 'PACE',
          colorHex: readings.paceYesterdayColor ?? readings.paceTodayColor,
          observationTime: readings.paceObservationTime,
          isToday: readings.paceYesterdayColor == null &&
              readings.paceTodayColor != null,
          showEstimate: showEstimates,
        ),
        _buildSatelliteColorRow(
          name: 'NOAA-20',
          colorHex:
              readings.noaa20YesterdayColor ?? readings.noaa20TodayColor,
          observationTime: readings.noaa20ObservationTime,
          isToday: readings.noaa20YesterdayColor == null &&
              readings.noaa20TodayColor != null,
          showEstimate: showEstimates,
        ),
        _buildSatelliteColorRow(
          name: 'NOAA-21',
          colorHex:
              readings.noaa21YesterdayColor ?? readings.noaa21TodayColor,
          observationTime: readings.noaa21ObservationTime,
          isToday: readings.noaa21YesterdayColor == null &&
              readings.noaa21TodayColor != null,
          showEstimate: showEstimates,
        ),
        _buildSatelliteColorRow(
          name: 'Sentinel-3A',
          colorHex: readings.sentinel3aYesterdayColor ??
              readings.sentinel3aTodayColor,
          observationTime: null,
          isToday: readings.sentinel3aYesterdayColor == null &&
              readings.sentinel3aTodayColor != null,
          showEstimate: showEstimates,
        ),
        _buildSatelliteColorRow(
          name: 'Sentinel-3B',
          colorHex: readings.sentinel3bYesterdayColor ??
              readings.sentinel3bTodayColor,
          observationTime: null,
          isToday: readings.sentinel3bYesterdayColor == null &&
              readings.sentinel3bTodayColor != null,
          isLast: true,
          showEstimate: showEstimates,
        ),
      ],
    );
  }

  Widget _buildBlendedEstimateRow(GibsSatelliteReadings readings, {bool highlight = false}) {
    final blended = _estimateFromSatelliteColors(readings);
    if (blended == null) return const SizedBox.shrink();

    final info = _getVisibilityInfo(blended);
    final highlightColor = info.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: highlight ? 10 : 0),
      decoration: BoxDecoration(
        color: highlight
            ? highlightColor.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: highlight
            ? Border.all(color: highlightColor.withValues(alpha: 0.4))
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'BLENDED',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: info.color,
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '${blended.toStringAsFixed(2)} mg/m\u00B3',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
            ),
          ),
          Expanded(
            child: Text(
              info.label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteColorRow({
    required String name,
    required String? colorHex,
    required DateTime? observationTime,
    bool isToday = false,
    bool isLast = false,
    bool showEstimate = false,
  }) {
    if (colorHex == null) return const SizedBox.shrink();

    final estChl = showEstimate ? estimateChlorophyllFromHex(colorHex) : null;

    return Container(
      padding: EdgeInsets.only(top: 8, bottom: isLast ? 4 : 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _parseHexColor(colorHex),
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
          ),
          if (estChl != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${estChl.toStringAsFixed(2)} mg/m\u00B3',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ),
          Expanded(
            child: Text(
              observationTime != null
                  ? _formatDateTime(observationTime)
                  : (isToday ? 'Today' : 'Yesterday'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // --- Bottom sheets ---

  /// Shows the visibility label legend: what each label means.
  void _showLabelLegend(BuildContext context) {
    final labels = [
      ('Crystal clear', '< 0.1', const Color(0xFF4400AA), 'Open ocean clarity'),
      ('Blue water', '0.1 – 0.3', const Color(0xFF0066FF), 'Great visibility'),
      ('Slight haze', '0.3 – 0.5', const Color(0xFF00CCAA), 'Visibility slightly reduced'),
      ('Green tint', '0.5 – 1.0', const Color(0xFFAADD00), 'Water shifting blue to green'),
      ('Murky', '1.0 – 3.0', const Color(0xFFFFCC00), 'Limited visibility'),
      ("Can't see your fins", '3.0 – 5.0', const Color(0xFFFF8800), 'Very poor'),
      ("Can't see your hand", '5.0 – 10.0', const Color(0xFFFF4400), 'Dense bloom'),
      ('Zero vis', '> 10.0', const Color(0xFF880000), 'Severe bloom'),
    ];

    // Highlight the current label
    final currentLabel = _getVisibilityInfo(
      widget.readings?.noaaErddapChlorophyll,
    ).label;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Visibility Scale',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Based on satellite chlorophyll-a concentration (mg/m\u00B3). Lower chlorophyll means clearer water.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            ...labels.map((entry) {
              final (label, range, color, desc) = entry;
              final isCurrent = label == currentLabel;
              return Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? color.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isCurrent
                      ? Border.all(color: color.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        range,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Shows comprehensive satellite info bottom sheet.
  void _showSatelliteInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Understanding Visibility',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),

            // TL;DR
            const SizedBox(height: 12),
            const Text(
              'We estimate underwater visibility using chlorophyll-a '
              'concentration measured by satellites. Less chlorophyll '
              'means less plankton means clearer water.',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),

            // How it works
            const SizedBox(height: 24),
            _aboutSectionHeader('HOW IT WORKS'),
            const SizedBox(height: 10),
            const Text(
              'Satellites measure ocean color from space. Greener water '
              'has more phytoplankton (tiny plants), which produce '
              'chlorophyll-a. We convert that chlorophyll number into '
              'a visibility rating you can relate to — from "Crystal '
              'clear" to "Zero vis."',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),

            // Visibility scale explained
            const SizedBox(height: 24),
            _aboutSectionHeader('VISIBILITY SCALE'),
            const SizedBox(height: 10),
            const Text(
              'The scale maps chlorophyll concentration (mg/m\u00B3) to '
              'a description of what you\'ll actually experience in the '
              'water. The highlighted row is your current reading.',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ranges are based on real-world observations in coastal '
              'and offshore environments. They won\'t be perfect '
              'everywhere — local factors like sediment, runoff, and '
              'currents also affect what you see.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.4),
            ),

            // Data sources — the two tiers
            const SizedBox(height: 24),
            _aboutSectionHeader('DATA SOURCES'),
            const SizedBox(height: 10),
            const Text(
              'We pull from two tiers of satellite data. The app '
              'automatically picks the best available source.',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),

            // #1 Copernicus
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#1 PREFERRED — COPERNICUS MARINE',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Copernicus Marine Service (run by the EU) merges data '
                    'from multiple satellites into a single daily product. '
                    'Cloud gaps are filled, bad pixels are removed, and '
                    'sensors are cross-calibrated. This is the same data '
                    'used by ocean researchers and government agencies.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When available, this is what determines your visibility rating.',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12,
                        fontStyle: FontStyle.italic, height: 1.4),
                  ),
                ],
              ),
            ),

            // #2 NASA GIBS
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#2 FALLBACK — NASA GIBS',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When Copernicus data isn\'t available for a location, '
                    'we fall back to individual satellite passes from NASA\'s '
                    'Global Imagery Browse Services (GIBS). Each satellite '
                    'captures an ocean-color image as it flies over — we '
                    'extract the color at your spot and convert it to a '
                    'chlorophyll estimate.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The "Blended" value combines all available satellite '
                    'readings into a single estimate. Individual values are '
                    'shown below it so you can see how they compare.',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12,
                        fontStyle: FontStyle.italic, height: 1.4),
                  ),
                ],
              ),
            ),

            // Why two sources?
            const SizedBox(height: 24),
            _aboutSectionHeader('WHY TWO SOURCES?'),
            const SizedBox(height: 10),
            const Text(
              'Copernicus doesn\'t cover every coastal location, and its '
              'daily product can lag by a day or two. NASA GIBS imagery '
              'updates faster and covers more areas, but each pass is '
              'noisier — clouds, sun glare, and shallow water can throw '
              'off single-pass readings. Having both means you get the '
              'best of each: precision from Copernicus when possible, '
              'coverage from NASA GIBS when not.',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),

            // Color dots
            const SizedBox(height: 24),
            _aboutSectionHeader('READING THE COLOR DOTS'),
            const SizedBox(height: 10),
            const Text(
              'Each color dot represents one satellite\'s ocean-color '
              'reading at your spot, matched to the same color scale '
              'used on NASA\'s chlorophyll maps:',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _colorLegendDot(const Color(0xFF4400AA)),
                _colorLegendDot(const Color(0xFF0066FF)),
                _colorLegendDot(const Color(0xFF00CCAA)),
                const SizedBox(width: 6),
                const Text('Clear',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 16),
                _colorLegendDot(const Color(0xFFAADD00)),
                _colorLegendDot(const Color(0xFFFFCC00)),
                const SizedBox(width: 6),
                const Text('Moderate',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 16),
                _colorLegendDot(const Color(0xFFFF8800)),
                _colorLegendDot(const Color(0xFFFF4400)),
                _colorLegendDot(const Color(0xFF880000)),
                const SizedBox(width: 6),
                const Text('High chl',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'When multiple satellites agree, you can be more confident. '
              'If one is way off from the others, it may have hit a cloud '
              'edge or sun glint.',
              style: TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.4),
            ),

            // Satellites
            const SizedBox(height: 24),
            _aboutSectionHeader('SATELLITES'),
            const SizedBox(height: 10),
            const _SatelliteInfoRow(
                name: 'PACE OCI',
                desc: 'NASA\'s newest ocean-color sensor (launched 2024). '
                    'Hyperspectral — sees hundreds of wavelengths.'),
            const SizedBox(height: 6),
            const _SatelliteInfoRow(
                name: 'NOAA-20 / 21',
                desc: 'VIIRS sensors on NOAA polar-orbiting weather '
                    'satellites. Reliable, well-calibrated.'),
            const SizedBox(height: 6),
            const _SatelliteInfoRow(
                name: 'Sentinel-3A / 3B',
                desc: 'ESA satellites with OLCI sensors, designed '
                    'specifically for ocean and land color.'),
            const SizedBox(height: 8),
            const Text(
              'Copernicus merges data from these and additional sensors '
              'into its quality-controlled product.',
              style: TextStyle(
                  color: Colors.white38, fontSize: 11, height: 1.3),
            ),

            // Limitations
            const SizedBox(height: 24),
            _aboutSectionHeader('LIMITATIONS'),
            const SizedBox(height: 10),
            const Text(
              '\u2022  Satellites see the surface. Subsurface conditions '
              '(thermoclines, deep currents) aren\'t captured.\n'
              '\u2022  Near shore, sediment runoff and kelp can mimic '
              'chlorophyll, making water look worse than it is.\n'
              '\u2022  Cloud cover blocks satellite views entirely — '
              'readings may be from yesterday or older.\n'
              '\u2022  These are estimates, not guarantees. Always use '
              'your own judgment once you\'re on the water.',
              style: TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.6),
            ),

            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }

  static Widget _aboutSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }

  static Widget _colorLegendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  // --- Utilities ---

  Color _parseHexColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}
    return Colors.grey;
  }

  String _formatDateTime(DateTime utcTime) {
    final local = utcTime.toLocal();
    return DateFormat('MMM d @ h:mma').format(local);
  }
}

/// Helper widget for satellite info in the modal.
class _SatelliteInfoRow extends StatelessWidget {
  final String name;
  final String desc;

  const _SatelliteInfoRow({required this.name, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$name: ',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
