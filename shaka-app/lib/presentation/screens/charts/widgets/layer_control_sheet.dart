import 'package:flutter/material.dart';
import '../../../../data/models/ocean_layer.dart';

/// Bottom sheet for controlling layer visibility, opacity, and settings
class LayerControlSheet extends StatefulWidget {
  final Map<String, LayerState> layerStates;
  final String baseMap;
  final DateTime selectedDate;
  final Function(String layerId, bool enabled) onLayerToggle;
  final Function(String layerId, double opacity) onOpacityChange;
  final Function(String baseMap) onBaseMapChange;
  final Function(DateTime date) onDateChange;

  const LayerControlSheet({
    super.key,
    required this.layerStates,
    required this.baseMap,
    required this.selectedDate,
    required this.onLayerToggle,
    required this.onOpacityChange,
    required this.onBaseMapChange,
    required this.onDateChange,
  });

  @override
  State<LayerControlSheet> createState() => _LayerControlSheetState();
}

class _LayerControlSheetState extends State<LayerControlSheet> {
  late String _baseMap;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _baseMap = widget.baseMap;
    _selectedDate = widget.selectedDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
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
                  const Text(
                    'LAYERS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Base map selector
            _buildSection(
              title: 'Base Map',
              child: Row(
                children: [
                  _BaseMapOption(
                    label: 'Dark',
                    icon: Icons.dark_mode,
                    selected: _baseMap == 'dark',
                    onTap: () => _setBaseMap('dark'),
                  ),
                  _BaseMapOption(
                    label: 'Satellite',
                    icon: Icons.satellite_alt,
                    selected: _baseMap == 'satellite',
                    onTap: () => _setBaseMap('satellite'),
                  ),
                  _BaseMapOption(
                    label: 'Nautical',
                    icon: Icons.sailing,
                    selected: _baseMap == 'nautical',
                    onTap: () => _setBaseMap('nautical'),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Data overlays
            _buildSection(
              title: 'Data Overlays',
              child: Column(
                children: widget.layerStates.values.map((state) {
                  return _LayerRow(
                    key: ValueKey('layer_${state.layer.id}_${state.enabled}_${state.opacity}'),
                    state: state,
                    onToggle: (enabled) {
                      widget.onLayerToggle(state.layer.id, enabled);
                      Navigator.pop(context); // Close sheet so map rebuilds
                    },
                    onOpacityChange: (opacity) {
                      widget.onOpacityChange(state.layer.id, opacity);
                    },
                  );
                }).toList(),
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Time selector
            _buildSection(
              title: 'Time',
              child: _buildTimeScrubber(),
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _setBaseMap(String map) {
    setState(() => _baseMap = map);
    widget.onBaseMapChange(map);
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTimeScrubber() {
    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: 14));
    final maxDate = now.subtract(const Duration(days: 1));
    
    final days = maxDate.difference(minDate).inDays;
    final currentDay = _selectedDate.difference(minDate).inDays;
    final progress = currentDay / days;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _selectedDate.isAfter(minDate) ? () {
                final newDate = _selectedDate.subtract(const Duration(days: 1));
                setState(() => _selectedDate = newDate);
                widget.onDateChange(newDate);
              } : null,
            ),
            Text(
              _formatDate(_selectedDate),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: _selectedDate.isBefore(maxDate) ? () {
                final newDate = _selectedDate.add(const Duration(days: 1));
                setState(() => _selectedDate = newDate);
                widget.onDateChange(newDate);
              } : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.cyan,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.cyan,
            overlayColor: Colors.cyan.withOpacity(0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final dayOffset = (value * days).round();
              final newDate = minDate.add(Duration(days: dayOffset));
              setState(() => _selectedDate = newDate);
              widget.onDateChange(newDate);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatShortDate(minDate),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const Text(
              '← 14 days of historical data →',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              _formatShortDate(maxDate),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatShortDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

class _BaseMapOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BaseMapOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.cyan.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.cyan : Colors.white12,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? Colors.cyan : Colors.white54,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.cyan : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerRow extends StatefulWidget {
  final LayerState state;
  final Function(bool) onToggle;
  final Function(double) onOpacityChange;

  const _LayerRow({
    super.key,
    required this.state,
    required this.onToggle,
    required this.onOpacityChange,
  });

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final layer = widget.state.layer;
    final enabled = widget.state.enabled;
    final opacity = widget.state.opacity;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: enabled ? layer.color.withOpacity(0.15) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? layer.color.withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          // Main row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Toggle switch
                  Switch(
                    value: enabled,
                    onChanged: widget.onToggle,
                    activeColor: layer.color,
                  ),
                  const SizedBox(width: 8),
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: layer.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      layer.icon,
                      color: enabled ? layer.color : Colors.white38,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          layer.name,
                          style: TextStyle(
                            color: enabled ? Colors.white : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Updates every ${_formatDuration(layer.updateFrequency)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Opacity indicator / expand
                  if (enabled)
                    Text(
                      '${(opacity * 100).round()}%',
                      style: TextStyle(
                        color: layer.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),

          // Expanded opacity control
          if (_expanded && enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.description,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Opacity',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: layer.color,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: layer.color,
                            overlayColor: layer.color.withOpacity(0.2),
                          ),
                          child: Slider(
                            value: opacity,
                            onChanged: widget.onOpacityChange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays} day${d.inDays > 1 ? 's' : ''}';
    if (d.inHours > 0) return '${d.inHours} hour${d.inHours > 1 ? 's' : ''}';
    return '${d.inMinutes} min';
  }
}
