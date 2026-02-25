import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';
import '../utils/gibs_colormap.dart';

/// Visibility label derived from chlorophyll concentration.
/// Matches the backend ShakaScorer thresholds exactly.
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

    // Use ERDDAP chlorophyll if available; otherwise estimate from satellite colors
    double? effectiveChl = readings.noaaErddapChlorophyll;
    bool isEstimated = false;
    if (effectiveChl == null) {
      effectiveChl = _estimateFromSatelliteColors(readings);
      isEstimated = effectiveChl != null;
    }

    var info = _getVisibilityInfo(effectiveChl);
    if (isEstimated) {
      info = _VisibilityInfo(
        label: '${info.label} (est.)',
        color: info.color,
        description: info.description,
        range: info.range,
      );
    }
    if (widget.visibilityScore != null) {
      final scoreColor = AppColors.getScoreColor(widget.visibilityScore!);
      info = _VisibilityInfo(
        label: info.label,
        color: scoreColor,
        description: info.description,
        range: info.range,
      );
    }

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
            // Info button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showLabelLegend(context);
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.white38,
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

          // Measured Chlorophyll
          if (readings.noaaErddapChlorophyll != null) ...[
            _buildMeasuredChlorophyllSection(readings, info),
            const SizedBox(height: 12),
          ],

          // Estimated Chlorophyll (when ERDDAP unavailable but satellite colors exist)
          if (readings.noaaErddapChlorophyll == null && estimatedChl != null) ...[
            _buildEstimatedChlorophyllSection(estimatedChl),
            const SizedBox(height: 12),
          ],

          // Legend
          _buildLegend(),
          const SizedBox(height: 16),

          // Satellite imagery
          _buildSatelliteImagerySection(readings),
        ],
      ),
    );
  }

  /// Measured chlorophyll (NOAA ERDDAP) — compact version.
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
                'MEASURED CHLOROPHYLL',
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
                  'TRUSTED',
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
            'Source: NOAA ERDDAP',
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
                'ESTIMATED FROM IMAGERY',
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
                  'ESTIMATED',
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
            'Derived from satellite imagery colors (may include sediment/kelp)',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
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
  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: _legendColors),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in ['0.01', '0.1', '0.5', '3.0', '20.0'])
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
          ],
        ),
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

    final showEstimates = readings.noaaErddapChlorophyll == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SATELLITE IMAGERY',
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
        const SizedBox(height: 12),
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
            width: 80,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
          if (estChl != null) ...[
            const SizedBox(width: 8),
            Text(
              estChl.toStringAsFixed(2),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          Expanded(
            child: Text(
              observationTime != null
                  ? _formatDateTime(observationTime)
                  : (isToday ? 'Today' : 'Yesterday'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.right,
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

  /// Shows satellite info bottom sheet.
  void _showSatelliteInfo(BuildContext context) {
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
                    'About Satellite Data',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MEASURED CHLOROPHYLL',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Trusted chlorophyll from quality-controlled satellite data '
                    'with coastal contamination filtered out.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SATELLITE IMAGERY COLORS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Raw satellite colors — may include sediment, kelp, or '
                    'shallow bottom reflectance in coastal areas.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SATELLITES',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 8),
                  _SatelliteInfoRow(
                      name: 'PACE', desc: 'NASA hyperspectral (2024)'),
                  _SatelliteInfoRow(
                      name: 'NOAA-20/21', desc: 'VIIRS ocean color'),
                  _SatelliteInfoRow(
                      name: 'Sentinel-3A/B', desc: 'ESA OLCI sensor'),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
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
