import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../data/models/spot_models.dart';

/// Card displaying satellite chlorophyll readings from multiple NASA/ESA satellites.
/// Shows data from PACE, NOAA-20, NOAA-21, Sentinel-3A, and Sentinel-3B.
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
          // Legend at top
          _buildLegend(),
          const SizedBox(height: 14),
          
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Chlorophyll-a (mg/m³)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
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
                        'About data',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Satellite rows - each on one line with color circle
          _buildSatelliteRow(
            name: 'PACE',
            value: readings!.paceYesterday ?? readings!.paceToday,
            colorHex: readings!.paceYesterdayColor ?? readings!.paceTodayColor,
            observationTime: readings!.paceObservationTime,
            isToday: readings!.paceYesterday == null && readings!.paceToday != null,
          ),
          _buildSatelliteRow(
            name: 'NOAA-20',
            value: readings!.noaa20Yesterday ?? readings!.noaa20Today,
            colorHex: readings!.noaa20YesterdayColor ?? readings!.noaa20TodayColor,
            observationTime: readings!.noaa20ObservationTime,
            isToday: readings!.noaa20Yesterday == null && readings!.noaa20Today != null,
          ),
          _buildSatelliteRow(
            name: 'NOAA-21',
            value: readings!.noaa21Yesterday ?? readings!.noaa21Today,
            colorHex: readings!.noaa21YesterdayColor ?? readings!.noaa21TodayColor,
            observationTime: readings!.noaa21ObservationTime,
            isToday: readings!.noaa21Yesterday == null && readings!.noaa21Today != null,
          ),
          _buildSatelliteRow(
            name: 'Sentinel-3A',
            value: readings!.sentinel3aYesterday ?? readings!.sentinel3aToday,
            colorHex: readings!.sentinel3aYesterdayColor ?? readings!.sentinel3aTodayColor,
            observationTime: null,
            isToday: readings!.sentinel3aYesterday == null && readings!.sentinel3aToday != null,
          ),
          _buildSatelliteRow(
            name: 'Sentinel-3B',
            value: readings!.sentinel3bYesterday ?? readings!.sentinel3bToday,
            colorHex: readings!.sentinel3bYesterdayColor ?? readings!.sentinel3bTodayColor,
            observationTime: null,
            isToday: readings!.sentinel3bYesterday == null && readings!.sentinel3bToday != null,
            isLast: readings!.noaaErddapChlorophyll == null,
          ),
          // NOAA ERDDAP (separate data source from GIBS imagery - NO color available)
          _buildSatelliteRow(
            name: 'NOAA-ERDDAP',
            value: readings!.noaaErddapChlorophyll,
            colorHex: null, // No color for ERDDAP - it's a direct numerical API
            observationTime: readings!.noaaErddapFetchTime,
            isToday: false, // This is fetched data, not "today's" observation
            isLast: true,
          ),
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
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0.01',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
            Text(
              'Clearer ← → Murkier',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
              ),
            ),
            Text(
              '50+',
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

  /// Build a single satellite row with name, color circle, value, and datetime all aligned
  Widget _buildSatelliteRow({
    required String name,
    required double? value,
    required String? colorHex,
    required DateTime? observationTime,
    bool isToday = false,
    bool isLast = false,
  }) {
    // Skip if no data
    if (value == null) {
      return const SizedBox.shrink();
    }
    
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
        children: [
          // Satellite name (fixed width)
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
          // Color circle from satellite imagery (or empty space for NOAA-ERDDAP)
          SizedBox(
            width: 24,
            child: colorHex != null
                ? Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _parseHexColor(colorHex),
                      border: Border.all(
                        color: Colors.white24,
                        width: 0.5,
                      ),
                    ),
                  )
                : const SizedBox.shrink(), // No circle for NOAA-ERDDAP
          ),
          // Value (3 decimal places)
          SizedBox(
            width: 55,
            child: Text(
              value.toStringAsFixed(3),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          // Timestamp or "Today"/"Yesterday"
          Expanded(
            child: Text(
              observationTime != null 
                  ? _formatDateTime(observationTime)
                  : (isToday ? 'Today' : 'Yesterday'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
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
    final formatter = DateFormat('MMM d, h:mm a');
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
                    'Satellite Chlorophyll Data',
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
            _buildInfoRow('Source', 'NASA GIBS & CMR'),
            _buildInfoRow('Updates', 'Daily satellite passes'),
            const SizedBox(height: 12),
            const Text(
              'Chlorophyll-a concentration indicates plankton density, which affects water clarity. '
              'Lower values (< 0.5 mg/m³) mean clearer water with better visibility for diving and snorkeling. '
              'Higher values suggest more plankton activity, potentially attracting baitfish.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
