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
    
    // In compact mode, expand to fill available space
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gradient bar - full width
          if (displayColors.isNotEmpty)
            Container(
              height: gradientHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: displayColors),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          if (displayColors.isNotEmpty && displayLabels.isNotEmpty)
            const SizedBox(height: 4),
          // Labels row - for GIBS: min | center (category unit) | max
          // For Copernicus: all ticks spread evenly
          if (displayLabels.isNotEmpty)
            _buildLabelsRow(displayLabels, centerLabel, fontSize),
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
  
  /// Build the labels row - handles both GIBS (3 labels with center) and Copernicus (many ticks)
  Widget _buildLabelsRow(List<String> displayLabels, String? centerLabel, double fontSize) {
    // For GIBS style with center label (3 items: min, center, max)
    if (centerLabel != null && displayLabels.length >= 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            displayLabels.first,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            centerLabel,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: fontSize - 1,
            ),
          ),
          Text(
            displayLabels.last,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    
    // For Copernicus style (all ticks evenly spread)
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: displayLabels.map((t) => Text(
        t,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      )).toList(),
    );
  }
}
