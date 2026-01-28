import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/api/copernicus_wmts_service.dart';
import '../../../../data/models/ocean_layer.dart';

/// Floating data bar at top of screen showing live values at crosshair
class FloatingDataBar extends StatelessWidget {
  final LatLng? position;
  final Map<String, FeatureInfo?> featureData;
  final bool isLoading;
  final List<LayerState> enabledLayers;
  final VoidCallback onBackPressed;

  const FloatingDataBar({
    super.key,
    required this.position,
    required this.featureData,
    required this.isLoading,
    required this.enabledLayers,
    required this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: onBackPressed,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Data chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Coordinate chip
                  if (position != null)
                    _DataChip(
                      icon: Icons.location_on,
                      value: _formatCoordinates(position!),
                      color: Colors.white70,
                    ),
                  
                  // Layer data chips
                  for (var state in enabledLayers)
                    _buildLayerChip(state),
                ],
              ),
            ),
          ),

          // Loading indicator
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLayerChip(LayerState state) {
    final info = featureData[state.layer.id];
    final hasValue = info?.hasValue ?? false;

    return _DataChip(
      icon: state.layer.icon,
      value: hasValue ? info!.displayValue : '--',
      color: state.layer.color,
      label: state.layer.shortName,
    );
  }

  String _formatCoordinates(LatLng pos) {
    final lat = pos.latitude.abs().toStringAsFixed(2);
    final latDir = pos.latitude >= 0 ? 'N' : 'S';
    final lon = pos.longitude.abs().toStringAsFixed(2);
    final lonDir = pos.longitude >= 0 ? 'E' : 'W';
    return '$lat°$latDir, $lon°$lonDir';
  }
}

class _DataChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final String? label;

  const _DataChip({
    required this.icon,
    required this.value,
    required this.color,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
