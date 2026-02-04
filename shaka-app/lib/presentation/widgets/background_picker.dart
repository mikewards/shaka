import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/map_background.dart';
import '../../data/services/map_background_service.dart';

/// Shows a bottom sheet to pick map background
/// 
/// If [currentSelection] and [onSelected] are provided, the picker operates in
/// "decoupled mode" where it shows the provided selection and calls the callback
/// instead of updating the shared MapBackgroundService. This allows screens like
/// GIBS to have their own independent map style preference.
void showBackgroundPicker(
  BuildContext context, {
  MapBackground? currentSelection,
  void Function(MapBackground)? onSelected,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => BackgroundPickerSheet(
      currentSelection: currentSelection,
      onSelected: onSelected,
    ),
  );
}

class BackgroundPickerSheet extends StatelessWidget {
  /// Optional: current selection for decoupled mode
  final MapBackground? currentSelection;
  
  /// Optional: callback for decoupled mode (instead of using shared service)
  final void Function(MapBackground)? onSelected;
  
  const BackgroundPickerSheet({
    super.key,
    this.currentSelection,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bgService = MapBackgroundService();
    
    // Use decoupled mode if callback is provided
    final isDecoupled = onSelected != null;
    
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
          
          // Background options - full width row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: isDecoupled
                // Decoupled mode: use provided selection
                ? Row(
                    children: MapBackground.values.map((bg) {
                      final isSelected = currentSelection == bg;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: bg == MapBackground.values.first ? 0 : 6,
                            right: bg == MapBackground.values.last ? 0 : 6,
                          ),
                          child: _BackgroundOption(
                            background: bg,
                            isSelected: isSelected,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onSelected!(bg);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  )
                // Shared service mode: use MapBackgroundService
                : ListenableBuilder(
                    listenable: bgService,
                    builder: (context, _) {
                      return Row(
                        children: MapBackground.values.map((bg) {
                          final isSelected = bgService.current == bg;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: bg == MapBackground.values.first ? 0 : 6,
                                right: bg == MapBackground.values.last ? 0 : 6,
                              ),
                              child: _BackgroundOption(
                                background: bg,
                                isSelected: isSelected,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  bgService.setBackground(bg);
                                  Navigator.pop(context);
                                },
                              ),
                            ),
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
        return AppColors.info;
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
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          padding: const EdgeInsets.all(8),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getIcon(),
                color: isSelected ? iconColor : Colors.white54,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                background.displayName,
                style: TextStyle(
                  color: isSelected ? iconColor : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
