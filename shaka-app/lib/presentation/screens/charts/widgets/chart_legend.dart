import 'package:flutter/material.dart';
import '../../../../data/models/ocean_layer.dart';

/// Collapsible legend showing colormap for enabled layers
class ChartLegend extends StatefulWidget {
  final List<LayerState> enabledLayers;
  final VoidCallback onClose;

  const ChartLegend({
    super.key,
    required this.enabledLayers,
    required this.onClose,
  });

  @override
  State<ChartLegend> createState() => _ChartLegendState();
}

class _ChartLegendState extends State<ChartLegend> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.enabledLayers.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.expand_less,
                    color: Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Legend',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Legend items
          if (_expanded)
            ...widget.enabledLayers.map((state) => _LegendItem(layer: state.layer)),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final OceanLayer layer;

  const _LegendItem({required this.layer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Layer name
          Row(
            children: [
              Icon(layer.icon, color: layer.color, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  layer.shortName,
                  style: TextStyle(
                    color: layer.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Colormap gradient
          Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: _getGradient(),
            ),
          ),
          const SizedBox(height: 4),

          // Value labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatValue(layer.minValue),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
              Text(
                layer.unit,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                ),
              ),
              Text(
                _formatValue(layer.maxValue),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LinearGradient _getGradient() {
    // Approximate gradients for each colormap
    switch (layer.id) {
      case 'sst':
        // Thermal colormap
        return const LinearGradient(
          colors: [
            Color(0xFF000030),
            Color(0xFF0000FF),
            Color(0xFF00FFFF),
            Color(0xFF00FF00),
            Color(0xFFFFFF00),
            Color(0xFFFF6600),
            Color(0xFFFF0000),
          ],
        );
      case 'chl':
      case 'zsd':
        // Viridis colormap
        return const LinearGradient(
          colors: [
            Color(0xFF440154),
            Color(0xFF3B528B),
            Color(0xFF21918C),
            Color(0xFF5EC962),
            Color(0xFFFDE725),
          ],
        );
      case 'ssh':
        // Balance colormap (diverging)
        return const LinearGradient(
          colors: [
            Color(0xFF3B3B8E),
            Color(0xFF8888DD),
            Color(0xFFEEEEEE),
            Color(0xFFDD8888),
            Color(0xFF8E3B3B),
          ],
        );
      case 'cur':
        // Speed colormap
        return const LinearGradient(
          colors: [
            Color(0xFFFFFFBF),
            Color(0xFFFED98E),
            Color(0xFFFE9929),
            Color(0xFFD95F0E),
            Color(0xFF993404),
          ],
        );
      default:
        return const LinearGradient(
          colors: [Colors.blue, Colors.cyan, Colors.green, Colors.yellow, Colors.red],
        );
    }
  }

  String _formatValue(double value) {
    if (layer.id == 'sst') {
      // Convert to Fahrenheit for display
      final f = value * 9 / 5 + 32;
      return '${f.round()}°F';
    }
    if (value >= 1) return value.round().toString();
    return value.toStringAsFixed(2);
  }
}
