import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/map_background.dart';
import '../../data/services/map_background_service.dart';

/// Shows a bottom sheet to pick map background
void showBackgroundPicker(BuildContext context) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const BackgroundPickerSheet(),
  );
}

class BackgroundPickerSheet extends StatelessWidget {
  const BackgroundPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bgService = MapBackgroundService();
    
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
          
          // Title
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Map Style',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // Background options grid
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ListenableBuilder(
              listenable: bgService,
              builder: (context, _) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: MapBackground.values.map((bg) {
                    final isSelected = bgService.current == bg;
                    return _BackgroundOption(
                      background: bg,
                      isSelected: isSelected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        bgService.setBackground(bg);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
          
          // Safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _BackgroundOption extends StatelessWidget {
  final MapBackground background;
  final bool isSelected;
  final VoidCallback onTap;

  const _BackgroundOption({
    required this.background,
    required this.isSelected,
    required this.onTap,
  });

  IconData _getIcon() {
    switch (background) {
      case MapBackground.defaultDark:
        return Icons.map;
      case MapBackground.satellite:
        return Icons.satellite_alt;
      case MapBackground.nauticalChart:
        return Icons.sailing;
    }
  }

  Color _getIconColor() {
    switch (background) {
      case MapBackground.defaultDark:
        return const Color(0xFF5B9BD5);
      case MapBackground.satellite:
        return const Color(0xFF4CAF50);
      case MapBackground.nauticalChart:
        return const Color(0xFF26A69A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor();
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? iconColor.withOpacity(0.15) 
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? iconColor : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIcon(),
              color: isSelected ? iconColor : Colors.white54,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              background.displayName,
              style: TextStyle(
                color: isSelected ? iconColor : Colors.white70,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
