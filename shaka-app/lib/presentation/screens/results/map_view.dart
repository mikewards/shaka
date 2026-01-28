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
            // Base map layer (OpenStreetMap)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.shaka.app',
              tileBuilder: _darkTileBuilder,
            ),

            // Spot markers
            MarkerLayer(
              markers: widget.spots.map((spot) {
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
                    child: _SpotMarker(
                      score: spot.shakaScore,
                      isSelected: _selectedSpot?.id == spot.id,
                    ),
                  ),
                );
              }).toList(),
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

  // Custom tile builder for ocean-themed map
  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.9, 0, 0, 0, 0,
        0, 0.9, 0, 0, 0,
        0, 0, 1.1, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

class _SpotMarker extends StatelessWidget {
  final int score;
  final bool isSelected;

  const _SpotMarker({
    required this.score,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getScoreColor(score);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isSelected ? 44 : 36,
      height: isSelected ? 44 : 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: isSelected ? 12 : 8,
            spreadRadius: isSelected ? 2 : 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            color: Colors.white,
            fontSize: isSelected ? 14 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ShakaScoreBadge(
              score: spot.shakaScore,
              confidence: spot.confidence,
              size: ShakaScoreSize.small,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spot.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        spot.access == 'shore'
                            ? Icons.beach_access
                            : Icons.directions_boat,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        spot.access.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.visibility, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        spot.conditions.visibility,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
          _LegendItem(color: AppColors.scoreGood, label: '60-79'),
          const SizedBox(height: 4),
          _LegendItem(color: AppColors.scoreFair, label: '40-59'),
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
