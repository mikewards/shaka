import 'package:flutter/material.dart';

/// A unified widget that displays a color legend for ocean chart layers
/// Supports both:
/// - Copernicus: CSS gradient string + tick values extracted from WebView
/// - GIBS: Direct color array + labels from layer model
class DynamicOceanLegend extends StatelessWidget {
  // For Copernicus (CSS gradient + ticks from JS)
  final String? gradientCss;
  final List<String>? ticks;
  
  // For GIBS (explicit colors + labels from model)
  final List<Color>? colors;
  final List<String>? labels;
  final String? unit;
  final String? categoryName;
  
  final bool compact;

  const DynamicOceanLegend({
    super.key,
    // Copernicus params
    this.gradientCss,
    this.ticks,
    // GIBS params
    this.colors,
    this.labels,
    this.unit,
    this.categoryName,
    // Shared
    this.compact = false,
  });
  
  /// Factory for Copernicus data
  factory DynamicOceanLegend.fromCopernicus({
    Key? key,
    required String? gradientCss,
    required List<String> ticks,
    bool compact = false,
  }) {
    return DynamicOceanLegend(
      key: key,
      gradientCss: gradientCss,
      ticks: ticks,
      compact: compact,
    );
  }
  
  /// Factory for GIBS data
  factory DynamicOceanLegend.fromGibs({
    Key? key,
    required List<Color> colors,
    required List<String> labels,
    String? unit,
    String? categoryName,
    bool compact = false,
  }) {
    return DynamicOceanLegend(
      key: key,
      colors: colors,
      labels: labels,
      unit: unit,
      categoryName: categoryName,
      compact: compact,
    );
  }

  /// Parse "linear-gradient(to right, rgb(255, 253, 205), rgb(254, 252, 203), ...)"
  /// into a list of Colors (for Copernicus CSS gradients)
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
  
  /// Get the colors to display (from either source)
  List<Color> _getColors() {
    // Prefer explicit colors (GIBS)
    if (colors != null && colors!.isNotEmpty) {
      return colors!;
    }
    // Fall back to parsing CSS gradient (Copernicus)
    return _parseGradientColors();
  }
  
  /// Get the labels to display
  List<String> _getLabels() {
    // Prefer explicit labels (GIBS)
    if (labels != null && labels!.isNotEmpty) {
      return labels!;
    }
    // Fall back to ticks (Copernicus)
    return ticks ?? [];
  }
  
  /// Get center label (category + unit for GIBS, empty for Copernicus)
  String? _getCenterLabel() {
    if (categoryName != null || unit != null) {
      final parts = <String>[];
      if (categoryName != null) parts.add(categoryName!);
      if (unit != null) parts.add(unit!);
      return parts.join(' ');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final displayColors = _getColors();
    final displayLabels = _getLabels();
    final centerLabel = _getCenterLabel();
    
    // Don't render if we have no data
    if (displayColors.isEmpty && displayLabels.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final gradientHeight = compact ? 12.0 : 12.0;
    final fontSize = compact ? 11.0 : 10.0;
    
    // In compact mode, expand to fill available space with tick marks
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient bar with tick marks
          if (displayColors.isNotEmpty)
            _buildGradientWithTicks(displayColors, displayLabels, gradientHeight, fontSize),
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
          if (displayColors.isNotEmpty)
            Container(
              width: gradientWidth,
              height: gradientHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: displayColors),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (displayColors.isNotEmpty && displayLabels.isNotEmpty)
            const SizedBox(height: 3),
          if (displayLabels.isNotEmpty)
            SizedBox(
              width: gradientWidth,
              child: _buildLabelsRow(displayLabels, centerLabel, fontSize),
            ),
        ],
      ),
    );
  }
  
  /// Build gradient bar with tick marks and labels at 0%, 25%, 50%, 75%, 100%
  Widget _buildGradientWithTicks(List<Color> displayColors, List<String> displayLabels, double gradientHeight, double fontSize) {
    // We need exactly 5 labels for 5 tick positions
    final tickLabels = displayLabels.length == 5 
        ? displayLabels 
        : _interpolateLabels(displayLabels, 5);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const tickHeight = 6.0;
        const tickWidth = 1.5;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient bar with tick marks
            SizedBox(
              height: gradientHeight + tickHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient bar
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      height: gradientHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: displayColors),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Tick marks at 0%, 25%, 50%, 75%, 100% - from top to below gradient
                  for (int i = 0; i < 5; i++)
                    Positioned(
                      left: i == 0 ? 0 : (i == 4 ? width - tickWidth : (width * i / 4) - (tickWidth / 2)),
                      top: 0,
                      child: Container(
                        width: tickWidth,
                        height: gradientHeight + tickHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 1,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Labels below tick marks
            Stack(
              children: [
                SizedBox(
                  height: fontSize + 4,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // First label (left-aligned)
                      Positioned(
                        left: 0,
                        child: Text(
                          tickLabels[0],
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Middle labels (centered on tick)
                      for (int i = 1; i < 4; i++)
                        Positioned(
                          left: (width * i / 4),
                          child: Transform.translate(
                            offset: Offset(-_measureText(tickLabels[i], fontSize) / 2, 0),
                            child: Text(
                              tickLabels[i],
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: fontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      // Last label (right-aligned)
                      Positioned(
                        right: 0,
                        child: Text(
                          tickLabels[4],
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
  
  /// Approximate text width for centering
  double _measureText(String text, double fontSize) {
    // Rough estimate: ~6px per character at 11pt font
    return text.length * (fontSize * 0.55);
  }
  
  /// Interpolate labels to get exactly count labels
  List<String> _interpolateLabels(List<String> labels, int count) {
    if (labels.isEmpty) return List.filled(count, '');
    if (labels.length == count) return labels;
    
    // Just distribute existing labels across positions
    final result = <String>[];
    for (int i = 0; i < count; i++) {
      final idx = (i * (labels.length - 1) / (count - 1)).round();
      result.add(labels[idx.clamp(0, labels.length - 1)]);
    }
    return result;
  }

  /// Build the labels row - all labels evenly spaced across full width
  Widget _buildLabelsRow(List<String> displayLabels, String? centerLabel, double fontSize) {
    // All labels evenly spaced across full width
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: displayLabels.map((label) => Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      )).toList(),
    );
  }
}
