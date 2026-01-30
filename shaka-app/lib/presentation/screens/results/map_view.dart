import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/spot_models.dart';
import '../../widgets/shaka_score_badge.dart';

class MapView extends StatefulWidget {
  final List<SpotSummary> spots;
  final double centerLat;
  final double centerLon;
  final Function(SpotSummary) onSpotTap;

  const MapView({
    super.key,
    required this.spots,
    required this.centerLat,
    required this.centerLon,
    required this.onSpotTap,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  SpotSummary? _selectedSpot;

  List<Marker> _buildMarkers() {
    return widget.spots.map((spot) {
      final color = _getMarkerColor(spot.shakaScore);
      return Marker(
        point: LatLng(spot.coordinates.lat, spot.coordinates.lon),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedSpot = spot;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${spot.shakaScore}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Color _getMarkerColor(int score) => AppColors.getScoreColor(score);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(widget.centerLat, widget.centerLon),
            initialZoom: 10,
            onTap: (_, __) {
              setState(() {
                _selectedSpot = null;
              });
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}@2x.png',
              userAgentPackageName: 'com.shaka.app',
            ),
            MarkerLayer(
              markers: _buildMarkers(),
            ),
          ],
        ),

        // Selected spot preview card
        if (_selectedSpot != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _SpotPreviewCard(
              spot: _selectedSpot!,
              onTap: () => widget.onSpotTap(_selectedSpot!),
              onClose: () {
                setState(() {
                  _selectedSpot = null;
                });
              },
            ),
          ),

        // Legend
        Positioned(
          top: 16,
          right: 16,
          child: _Legend(),
        ),
      ],
    );
  }
}

class _SpotPreviewCard extends StatelessWidget {
  final SpotSummary spot;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SpotPreviewCard({
    required this.spot,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Row(
              children: [
                ShakaScoreBadge(
                  score: spot.shakaScore,
                  confidence: spot.confidence,
                  size: ShakaScoreSize.small,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spot.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${spot.access.toUpperCase()} · ${spot.bestTimeOfDay}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 14),
            
            // Conditions row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ConditionItem(
                    label: 'Vis',
                    value: _extractVis(spot.conditions.visibility),
                  ),
                  _ConditionItem(
                    label: 'Temp',
                    value: _extractTemp(spot.conditions.waterTemp),
                  ),
                  _ConditionItem(
                    label: 'Swell',
                    value: _extractSwell(spot.conditions.swell),
                  ),
                  _ConditionItem(
                    label: 'Wind',
                    value: spot.conditions.wind,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // View indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tap for details',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '>',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _extractVis(String vis) {
    final match = RegExp(r'(\d+m)').firstMatch(vis);
    return match?.group(1) ?? vis;
  }

  String _extractTemp(String temp) {
    final match = RegExp(r'(\d+°F)').firstMatch(temp);
    return match?.group(1) ?? temp;
  }

  String _extractSwell(String swell) {
    final match = RegExp(r'([\d-]+ft)').firstMatch(swell);
    return match?.group(1) ?? swell;
  }
}

class _ConditionItem extends StatelessWidget {
  final String label;
  final String value;

  const _ConditionItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textMuted,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: AppColors.scoreExcellent, label: '80+'),
          const SizedBox(height: 4),
          _LegendItem(color: AppColors.scoreGood, label: '60+'),
          const SizedBox(height: 4),
          _LegendItem(color: AppColors.scoreFair, label: '40+'),
          const SizedBox(height: 4),
          _LegendItem(color: AppColors.scorePoor, label: '<40'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
