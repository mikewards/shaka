import 'package:flutter/material.dart';

/// A widget that displays a color legend for ocean chart layers
/// using actual gradient CSS and tick values extracted from Copernicus
class DynamicOceanLegend extends StatelessWidget {
  final String? gradientCss;
  final List<String> ticks;
  final bool compact;

  const DynamicOceanLegend({
    super.key,
    required this.gradientCss,
    required this.ticks,
    this.compact = false,
  });

  /// Parse "linear-gradient(to right, rgb(255, 253, 205), rgb(254, 252, 203), ...)"
  /// into a list of Colors
  List<Color> _parseGradientColors() {
    if (gradientCss == null || gradientCss!.isEmpty) return [];
    
    final rgbPattern = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)');
    final matches = rgbPattern.allMatches(gradientCss!);
    
    if (matches.isEmpty) return [];
    
    final allColors = matches.map((m) => Color.fromARGB(
      255,
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    )).toList();
    
    // If we have too many colors (Copernicus sends ~250), sample evenly
    // Flutter LinearGradient works better with fewer stops
    if (allColors.length > 20) {
      final step = allColors.length / 20;
      return List.generate(20, (i) => allColors[(i * step).floor().clamp(0, allColors.length - 1)]);
    }
    
    return allColors;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _parseGradientColors();
    
    // Don't render if we have no data
    if (colors.isEmpty && ticks.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final gradientHeight = compact ? 10.0 : 12.0;
    final fontSize = compact ? 9.0 : 10.0;
    
    // In compact mode, expand to fill available space
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient bar - full width
          if (colors.isNotEmpty)
            Container(
              height: gradientHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (colors.isNotEmpty && ticks.isNotEmpty)
            const SizedBox(height: 3),
          // Tick labels - full width
          if (ticks.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ticks.map((t) => Text(
                t,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
              )).toList(),
            ),
        ],
      );
    }
    
    // Non-compact mode with fixed width
    const gradientWidth = 200.0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (colors.isNotEmpty)
            Container(
              width: gradientWidth,
              height: gradientHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (colors.isNotEmpty && ticks.isNotEmpty)
            const SizedBox(height: 3),
          if (ticks.isNotEmpty)
            SizedBox(
              width: gradientWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ticks.map((t) => Text(
                  t,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
