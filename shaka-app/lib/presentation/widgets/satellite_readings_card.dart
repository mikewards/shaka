import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Card displaying satellite data in two sections:
/// 1. MEASURED CHLOROPHYLL - from NOAA ERDDAP (the trusted source)
/// 2. SATELLITE IMAGERY - colors from GIBS satellites (display only)
///
/// IMPORTANT: Satellite imagery colors are for display only and may include
/// sediment, kelp, or bottom reflectance in coastal areas. For actual
/// chlorophyll concentration, use the NOAA ERDDAP value.
class SatelliteReadingsCard extends StatelessWidget {
  final GibsSatelliteReadings? readings;

  // Dark theme colors (matching ConditionsCard)
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  // Chlorophyll legend colors (matching GIBS layer)
  static const _legendColors = [
    Color(0xFF4400AA), // Purple - very low (clearest)
    Color(0xFF0044FF), // Blue - low
    Color(0xFF00AAFF), // Light blue
    Color(0xFF00FFAA), // Cyan-green
    Color(0xFF00FF00), // Green - medium
    Color(0xFFAAFF00), // Yellow-green
    Color(0xFFFFFF00), // Yellow
    Color(0xFFFFAA00), // Orange
    Color(0xFFFF4400), // Red-orange - high
    Color(0xFF880000), // Dark red - very high (murky)
  ];

  const SatelliteReadingsCard({super.key, this.readings});

  @override
  Widget build(BuildContext context) {
    if (readings == null || !readings!.hasAnyData) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: const Center(
          child: Text(
            'Satellite data not available',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

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
          // SECTION 1: Measured Chlorophyll (NOAA ERDDAP)
          _buildMeasuredChlorophyllSection(),
          
          const SizedBox(height: 12),
          
          // Legend below measured chlorophyll
          _buildLegend(),
          
          const SizedBox(height: 16),
          
          // SECTION 2: Satellite Imagery (colors only)
          _buildSatelliteImagerySection(),
        ],
      ),
    );
  }

  /// Build the chlorophyll color legend
  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gradient bar
        Container(
          height: 12,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: _legendColors),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        // Labels - 5 values at logarithmic positions
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

  /// Section 1: Measured Chlorophyll from NOAA ERDDAP
  Widget _buildMeasuredChlorophyllSection() {
    if (readings!.noaaErddapChlorophyll == null) {
      return const SizedBox.shrink();
    }

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
              GestureDetector(
                onTap: () => _showInfo,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                readings!.noaaErddapChlorophyll!.toStringAsFixed(3),
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
                  'mg/m³',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              if (readings!.noaaErddapFetchTime != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _formatDateTime(readings!.noaaErddapFetchTime!),
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
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Section 2: Satellite Imagery (colors and timestamps only)
  Widget _buildSatelliteImagerySection() {
    final hasSatelliteColors = readings!.paceTodayColor != null ||
        readings!.paceYesterdayColor != null ||
        readings!.noaa20TodayColor != null ||
        readings!.noaa20YesterdayColor != null ||
        readings!.noaa21TodayColor != null ||
        readings!.noaa21YesterdayColor != null ||
        readings!.sentinel3aTodayColor != null ||
        readings!.sentinel3aYesterdayColor != null ||
        readings!.sentinel3bTodayColor != null ||
        readings!.sentinel3bYesterdayColor != null;

    if (!hasSatelliteColors) {
      return const SizedBox.shrink();
    }

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
            Builder(
              builder: (context) => GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showInfo(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Satellite rows - color and datetime only (no mg/m³ values)
        _buildSatelliteColorRow(
          name: 'PACE',
          colorHex: readings!.paceYesterdayColor ?? readings!.paceTodayColor,
          observationTime: readings!.paceObservationTime,
          isToday: readings!.paceYesterdayColor == null && readings!.paceTodayColor != null,
        ),
        _buildSatelliteColorRow(
          name: 'NOAA-20',
          colorHex: readings!.noaa20YesterdayColor ?? readings!.noaa20TodayColor,
          observationTime: readings!.noaa20ObservationTime,
          isToday: readings!.noaa20YesterdayColor == null && readings!.noaa20TodayColor != null,
        ),
        _buildSatelliteColorRow(
          name: 'NOAA-21',
          colorHex: readings!.noaa21YesterdayColor ?? readings!.noaa21TodayColor,
          observationTime: readings!.noaa21ObservationTime,
          isToday: readings!.noaa21YesterdayColor == null && readings!.noaa21TodayColor != null,
        ),
        _buildSatelliteColorRow(
          name: 'Sentinel-3A',
          colorHex: readings!.sentinel3aYesterdayColor ?? readings!.sentinel3aTodayColor,
          observationTime: null,
          isToday: readings!.sentinel3aYesterdayColor == null && readings!.sentinel3aTodayColor != null,
        ),
        _buildSatelliteColorRow(
          name: 'Sentinel-3B',
          colorHex: readings!.sentinel3bYesterdayColor ?? readings!.sentinel3bTodayColor,
          observationTime: null,
          isToday: readings!.sentinel3bYesterdayColor == null && readings!.sentinel3bTodayColor != null,
          isLast: true,
        ),
      ],
    );
  }

  /// Build a single satellite row with name, color circle, and datetime
  Widget _buildSatelliteColorRow({
    required String name,
    required String? colorHex,
    required DateTime? observationTime,
    bool isToday = false,
    bool isLast = false,
  }) {
    // Skip if no color data
    if (colorHex == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: isLast ? 4 : 8,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Colors.white10),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Satellite name (left)
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Color circle from satellite imagery (center)
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _parseHexColor(colorHex),
              border: Border.all(
                color: Colors.white24,
                width: 0.5,
              ),
            ),
          ),
          // Timestamp or "Today"/"Yesterday" (right)
          Expanded(
            child: Text(
              observationTime != null 
                  ? _formatDateTime(observationTime)
                  : (isToday ? 'Today' : 'Yesterday'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Parse hex color string "#RRGGBB" to Color
  Color _parseHexColor(String hexColor) {
    try {
      // Remove # if present
      final hex = hexColor.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (e) {
      // Fall back to gray if parsing fails
    }
    return Colors.grey;
  }

  /// Format observation time in user's local timezone
  String _formatDateTime(DateTime utcTime) {
    final local = utcTime.toLocal();
    final formatter = DateFormat('MMM d @ h:mma');
    return formatter.format(local);
  }

  void _showInfo(BuildContext context) {
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
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
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
                  SizedBox(height: 8),
                  Text(
                    'Trusted chlorophyll from quality-controlled satellite data '
                    'with coastal contamination filtered out.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
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
                    'Raw satellite colors - may include sediment, kelp, or '
                    'shallow bottom reflectance in coastal areas.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
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
                  _SatelliteInfoRow(name: 'PACE', desc: 'NASA hyperspectral (2024)'),
                  _SatelliteInfoRow(name: 'NOAA-20/21', desc: 'VIIRS ocean color'),
                  _SatelliteInfoRow(name: 'Sentinel-3A/B', desc: 'ESA OLCI sensor'),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Helper widget for satellite info in the modal
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
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
