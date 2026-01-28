import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  SpotSummary? _selectedSpot;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  void _buildMarkers() {
    _markers = widget.spots.map((spot) {
      final color = _getMarkerHue(spot.shakaScore);
      return Marker(
        markerId: MarkerId(spot.id),
        position: LatLng(spot.coordinates.lat, spot.coordinates.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(color),
        onTap: () {
          setState(() {
            _selectedSpot = spot;
          });
        },
      );
    }).toSet();
  }

  double _getMarkerHue(int score) {
    if (score >= 80) return BitmapDescriptor.hueGreen;
    if (score >= 60) return BitmapDescriptor.hueCyan;
    if (score >= 40) return BitmapDescriptor.hueYellow;
    return BitmapDescriptor.hueRed;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.centerLat, widget.centerLon),
            zoom: 10,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          markers: _markers,
          onTap: (_) {
            setState(() {
              _selectedSpot = null;
            });
          },
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
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
                      Text(
                        spot.access.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
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
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  '>',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
