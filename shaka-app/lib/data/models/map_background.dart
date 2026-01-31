/// Map background types available across the app
enum MapBackground {
  /// Dark cartography - default for the app
  defaultDark,
  
  /// Satellite/aerial imagery
  satellite,
  
  /// Nautical chart style with ocean depth coloring + nav markers
  nauticalChart,
}

/// Extension to get display info for each background
extension MapBackgroundExtension on MapBackground {
  String get displayName {
    switch (this) {
      case MapBackground.defaultDark:
        return 'Default';
      case MapBackground.satellite:
        return 'Satellite';
      case MapBackground.nauticalChart:
        return 'Nautical';
    }
  }
  
  String get description {
    switch (this) {
      case MapBackground.defaultDark:
        return 'Dark map style';
      case MapBackground.satellite:
        return 'Aerial imagery';
      case MapBackground.nauticalChart:
        return 'Ocean depths';
    }
  }
  
  /// Icon for the background type
  String get iconName {
    switch (this) {
      case MapBackground.defaultDark:
        return 'map';
      case MapBackground.satellite:
        return 'satellite_alt';
      case MapBackground.nauticalChart:
        return 'sailing';
    }
  }
}

/// Configuration for an overlay raster source
class RasterOverlayConfig {
  final String id;
  final String urlTemplate;
  final int tileSize;
  final double opacity;
  final double minZoom;
  final double maxZoom;
  
  const RasterOverlayConfig({
    required this.id,
    required this.urlTemplate,
    this.tileSize = 256,
    this.opacity = 1.0,
    this.minZoom = 0.0,
    this.maxZoom = 18.0,
  });
}
