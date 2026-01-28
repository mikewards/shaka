import 'package:flutter/material.dart';
import '../../../../data/models/ocean_layer.dart';

/// Minimal layer control sheet - Cash App inspired design
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
  double _globalOpacity = 0.8;
  // Track layer states locally for immediate UI feedback
  late Map<String, bool> _localLayerEnabled;

  @override
  void initState() {
    super.initState();
    _baseMap = widget.baseMap;
    _selectedDate = widget.selectedDate;
    _localLayerEnabled = {
      for (var entry in widget.layerStates.entries) entry.key: entry.value.enabled
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // DATE SELECTOR AT TOP
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildDateSelector(),
            ),

            const SizedBox(height: 20),

            // Base map chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildChip('Dark', _baseMap == 'dark', () => _setBaseMap('dark')),
                  const SizedBox(width: 8),
                  _buildChip('Satellite', _baseMap == 'satellite', () => _setBaseMap('satellite')),
                  const SizedBox(width: 8),
                  _buildChip('Nautical', _baseMap == 'nautical', () => _setBaseMap('nautical')),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Global opacity
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildOpacityRow(),
            ),

            const SizedBox(height: 16),

            // Section divider
            Container(
              height: 1,
              color: Colors.white10,
              margin: const EdgeInsets.symmetric(horizontal: 20),
            ),

            const SizedBox(height: 8),

            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DATA LAYERS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            // Layer toggles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: widget.layerStates.values.map((state) {
                  return _buildLayerRow(state);
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerRow(LayerState state) {
    // Use local state for immediate UI feedback
    final enabled = _localLayerEnabled[state.layer.id] ?? state.enabled;
    
    return GestureDetector(
      onTap: () {
        final newEnabled = !enabled;
        // Update local state immediately for instant UI feedback
        setState(() {
          _localLayerEnabled[state.layer.id] = newEnabled;
        });
        // Notify parent
        widget.onLayerToggle(state.layer.id, newEnabled);
        // Apply global opacity when enabling
        if (newEnabled) {
          widget.onOpacityChange(state.layer.id, _globalOpacity);
        }
        // Close the sheet to force map rebuild
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white10, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Layer icon
            Icon(
              state.layer.icon,
              color: enabled ? state.layer.color : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 12),
            // Layer name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.layer.name,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white54,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (enabled)
                    Text(
                      state.layer.description,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            // Pill toggle
            _buildPillToggle(enabled),
          ],
        ),
      ),
    );
  }

  Widget _buildPillToggle(bool enabled) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.white12,
        borderRadius: BorderRadius.circular(13),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: enabled ? Colors.black : Colors.white38,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: 14));
    final maxDate = now;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _selectedDate.isAfter(minDate)
              ? () {
                  final newDate = _selectedDate.subtract(const Duration(days: 1));
                  setState(() => _selectedDate = newDate);
                  widget.onDateChange(newDate);
                }
              : null,
          child: Icon(
            Icons.chevron_left,
            color: _selectedDate.isAfter(minDate) ? Colors.white : Colors.white24,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          _formatDate(_selectedDate),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: _selectedDate.isBefore(maxDate)
              ? () {
                  final newDate = _selectedDate.add(const Duration(days: 1));
                  setState(() => _selectedDate = newDate);
                  widget.onDateChange(newDate);
                }
              : null,
          child: Icon(
            Icons.chevron_right,
            color: _selectedDate.isBefore(maxDate) ? Colors.white : Colors.white24,
            size: 28,
          ),
        ),
      ],
    );
  }

  Widget _buildOpacityRow() {
    return Row(
      children: [
        Text(
          'Opacity',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: _globalOpacity,
              onChanged: (value) {
                setState(() => _globalOpacity = value);
                // Update all enabled layers
                for (var state in widget.layerStates.values) {
                  if (state.enabled) {
                    widget.onOpacityChange(state.layer.id, value);
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(_globalOpacity * 100).round()}%',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _setBaseMap(String map) {
    setState(() => _baseMap = map);
    widget.onBaseMapChange(map);
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
