import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/spot_models.dart';

/// Card displaying satellite chlorophyll readings from multiple NASA/ESA satellites.
/// Shows data from PACE, NOAA-20, NOAA-21, Sentinel-3A, and Sentinel-3B.
class SatelliteReadingsCard extends StatelessWidget {
  final GibsSatelliteReadings? readings;

  // Dark theme colors (matching ConditionsCard)
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

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
          // Header
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'About data',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 12, color: Colors.white38),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Satellite rows
          _buildSatelliteRow(
            name: 'PACE',
            today: readings!.paceToday,
            yesterday: readings!.paceYesterday,
            observationTime: readings!.paceObservationTime,
          ),
          _buildSatelliteRow(
            name: 'NOAA-20',
            today: readings!.noaa20Today,
            yesterday: readings!.noaa20Yesterday,
            observationTime: readings!.noaa20ObservationTime,
          ),
          _buildSatelliteRow(
            name: 'NOAA-21',
            today: readings!.noaa21Today,
            yesterday: readings!.noaa21Yesterday,
            observationTime: readings!.noaa21ObservationTime,
          ),
          _buildSatelliteRow(
            name: 'Sentinel-3A',
            today: readings!.sentinel3aToday,
            yesterday: readings!.sentinel3aYesterday,
            observationTime: null, // Not available from CMR
          ),
          _buildSatelliteRow(
            name: 'Sentinel-3B',
            today: readings!.sentinel3bToday,
            yesterday: readings!.sentinel3bYesterday,
            observationTime: null, // Not available from CMR
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteRow({
    required String name,
    required double? today,
    required double? yesterday,
    required DateTime? observationTime,
    bool isLast = false,
  }) {
    // Skip entirely empty satellites
    if (today == null && yesterday == null) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Satellite name
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          
          // Values row
          Row(
            children: [
              // Yesterday value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yesterday',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      yesterday != null ? yesterday.toStringAsFixed(2) : '—',
                      style: TextStyle(
                        color: yesterday != null ? Colors.white70 : Colors.white30,
                        fontSize: 13,
                      ),
                    ),
                    if (observationTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(observationTime),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Today value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      today != null ? today.toStringAsFixed(2) : '—',
                      style: TextStyle(
                        color: today != null ? Colors.white70 : Colors.white30,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format observation time in user's local timezone
  String _formatTime(DateTime utcTime) {
    final local = utcTime.toLocal();
    final formatter = DateFormat('MMM d, h:mm a');
    return formatter.format(local);
  }

  void _showInfo(BuildContext context) {
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
                    'Satellite Readings',
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
            _buildInfoRow(context, 'Source', 'NASA GIBS & CMR'),
            _buildInfoRow(context, 'Updates', 'Daily satellite passes'),
            const SizedBox(height: 12),
            Text(
              'Chlorophyll-a concentration from multiple ocean-color satellites. '
              'Lower values (< 0.5 mg/m³) indicate clearer water with better visibility. '
              'Higher values suggest more plankton activity.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Satellites:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSatelliteInfo(context, 'PACE', 'NASA hyperspectral (newest)'),
                  _buildSatelliteInfo(context, 'NOAA-20/21', 'VIIRS ocean color'),
                  _buildSatelliteInfo(context, 'Sentinel-3A/B', 'ESA OLCI sensor'),
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
            width: 80,
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteInfo(BuildContext context, String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$name: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
