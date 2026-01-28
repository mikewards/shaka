import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/api/copernicus_wmts_service.dart';
import '../../../../data/models/ocean_layer.dart';

/// Bottom sheet showing detailed data at a specific point
class PointDataCard extends StatefulWidget {
  final LatLng point;
  final List<LayerState> layerStates;
  final CopernicusWMTSService wmtsService;
  final DateTime selectedDate;

  const PointDataCard({
    super.key,
    required this.point,
    required this.layerStates,
    required this.wmtsService,
    required this.selectedDate,
  });

  @override
  State<PointDataCard> createState() => _PointDataCardState();
}

class _PointDataCardState extends State<PointDataCard> {
  Map<String, FeatureInfo?> _data = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final newData = <String, FeatureInfo?>{};

    for (var state in widget.layerStates) {
      final info = await widget.wmtsService.getFeatureInfo(
        layer: state.layer,
        point: widget.point,
        time: CopernicusWMTSService.formatTime(widget.selectedDate),
        zoom: 8,
      );
      newData[state.layer.id] = info;
    }

    if (mounted) {
      setState(() {
        _data = newData;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.pin_drop,
                    color: Colors.cyan,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Point Data',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatCoordinates(widget.point),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Date
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Text(
                  _formatDate(widget.selectedDate),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Data values
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.cyan),
              ),
            )
          else
            ...widget.layerStates.map((state) => _DataRow(
              layer: state.layer,
              info: _data[state.layer.id],
            )),

          const SizedBox(height: 8),

          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Save location
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Save location coming soon!')),
                      );
                    },
                    icon: const Icon(Icons.bookmark_border),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyan,
                      side: const BorderSide(color: Colors.cyan),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Share
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share coming soon!')),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  String _formatCoordinates(LatLng pos) {
    final lat = pos.latitude.abs().toStringAsFixed(4);
    final latDir = pos.latitude >= 0 ? 'N' : 'S';
    final lon = pos.longitude.abs().toStringAsFixed(4);
    final lonDir = pos.longitude >= 0 ? 'E' : 'W';
    return '$lat°$latDir, $lon°$lonDir';
  }

  String _formatDate(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _DataRow extends StatelessWidget {
  final OceanLayer layer;
  final FeatureInfo? info;

  const _DataRow({
    required this.layer,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = info?.hasValue ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: layer.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: layer.color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: layer.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              layer.icon,
              color: layer.color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (!hasValue)
                  const Text(
                    'No data at this location',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),

          // Value
          Text(
            hasValue ? info!.displayValue : '--',
            style: TextStyle(
              color: hasValue ? layer.color : Colors.white38,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
