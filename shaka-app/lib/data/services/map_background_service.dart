import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_background.dart';

/// Service for managing map background styles across the app.
/// Singleton pattern with ChangeNotifier for reactive updates.
class MapBackgroundService extends ChangeNotifier {
  static final MapBackgroundService _instance = MapBackgroundService._internal();
  factory MapBackgroundService() => _instance;
  MapBackgroundService._internal();
  
  static const String _prefKey = 'map_background';
  
  MapBackground _current = MapBackground.defaultDark;
  MapBackground get current => _current;
  
  /// Initialize from saved preference
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _current = MapBackground.values.firstWhere(
          (b) => b.name == saved,
          orElse: () => MapBackground.defaultDark,
        );
      }
    } catch (e) {
      debugPrint('Failed to load map background preference: $e');
    }
  }
  
  /// Set the current background
  Future<void> setBackground(MapBackground background) async {
    if (_current == background) return;
    
    _current = background;
    notifyListeners();
    
    // Persist preference
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, background.name);
    } catch (e) {
      debugPrint('Failed to save map background preference: $e');
    }
  }
  
  // ============================================================
  // TILE SOURCE URLS
  // ============================================================
  
  /// Carto Dark Matter - default dark style
  static const String cartoDarkStyle = 
    'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';
  
  /// Carto Positron - light style for nautical base
  static const String cartoLightStyle =
    'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';
  
  /// Carto Voyager - balanced style
  static const String cartoVoyagerStyle =
    'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json';
  
  // ============================================================
  // RASTER TILE SOURCES (Free, no API key required)
  // ============================================================
  
  /// EOX Sentinel-2 Cloudless satellite imagery (free, no API key)
  static const String eoxSatelliteTiles = 
    'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg';
  
  /// OpenTopoMap - topographic terrain (free)
  static const String openTopoMapTiles =
    'https://tile.opentopomap.org/{z}/{x}/{y}.png';
  
  /// OpenSeaMap - nautical navigation markers overlay (free)
  static const String openSeaMapTiles =
    'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png';
  
  /// GEBCO WMS - global bathymetry (free)
  /// Note: This is a WMS service, needs special handling
  static String gebcoBathymetryWMS(double west, double south, double east, double north) {
    return 'https://wms.gebco.net/mapserv?'
      'SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap'
      '&LAYERS=GEBCO_LATEST_SUB_ICE_TOPO'
      '&CRS=EPSG:3857&FORMAT=image/png&TRANSPARENT=true'
      '&WIDTH=256&HEIGHT=256'
      '&BBOX=$west,$south,$east,$north';
  }
  
  /// GEBCO bathymetry as XYZ-style tiles (using TMS endpoint)
  static const String gebcoTiles = 
    'https://www.gebco.net/data_and_products/gebco_web_services/2021/mapserv?'
    'request=GetTile&service=WMTS&version=1.0.0'
    '&layer=GEBCO_LATEST_SUB_ICE_TOPO&tilematrixset=EPSG:3857'
    '&tilematrix={z}&tilerow={y}&tilecol={x}&format=image/png';
  
  // ============================================================
  // STYLE URL GETTER
  // ============================================================
  
  /// ArcGIS World Imagery - high-res satellite (supports zoom 0-19)
  static const String arcgisWorldImagery =
    'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  
  /// ArcGIS Ocean basemap - bathymetry with depth contours (zoom 0-16)
  static const String arcgisOceanTiles =
    'https://services.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Base/MapServer/tile/{z}/{y}/{x}';
  
  /// ArcGIS Ocean reference (labels overlay)
  static const String arcgisOceanRefTiles =
    'https://services.arcgisonline.com/ArcGIS/rest/services/Ocean/World_Ocean_Reference/MapServer/tile/{z}/{y}/{x}';
  
  /// Stadia Alidade Smooth Dark - clean dark basemap with ocean detail (zoom 0-20)
  static const String stadiaAlidadeDark =
    'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}.png';
  
  /// CartoDB Dark with labels - for bathymetry overlay base
  static const String cartoDarkNoLabels =
    'https://basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}.png';

  /// Minimal dark style - just a dark background, no water styling
  /// This allows raster overlays to show through completely
  static const String _minimalDarkStyle = '''
{
  "version": 8,
  "name": "Minimal Dark",
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {
        "background-color": "#0D0D0D"
      }
    }
  ]
}
''';

  /// Get the base MapLibre style URL for a background type
  String getStyleUrl(MapBackground background) {
    switch (background) {
      case MapBackground.defaultDark:
        // Voyager - friendlier, balanced look with soft colors
        return cartoVoyagerStyle;
      case MapBackground.satellite:
        // Voyager base for fast loading, satellite overlay on top
        return cartoVoyagerStyle;
      case MapBackground.nauticalChart:
        // Light base for chart-like nautical appearance
        return cartoLightStyle;
    }
  }
  
  /// Get overlay raster sources to add after the base style loads
  List<RasterOverlayConfig> getOverlays(MapBackground background) {
    switch (background) {
      case MapBackground.defaultDark:
        return []; // No overlays needed
        
      case MapBackground.satellite:
        return [
          // ArcGIS World Imagery - THE GOLD high-res satellite (zoom 0-19)
          const RasterOverlayConfig(
            id: 'satellite',
            urlTemplate: arcgisWorldImagery,
            tileSize: 256,
            opacity: 1.0,
            maxZoom: 19.0,
          ),
        ];
        
      case MapBackground.nauticalChart:
        return [
          // ArcGIS Ocean - shows depth contours and bathymetry coloring
          const RasterOverlayConfig(
            id: 'ocean-base',
            urlTemplate: arcgisOceanTiles,
            tileSize: 256,
            opacity: 1.0,
            maxZoom: 16.0,
          ),
          // OpenSeaMap navigation markers (buoys, beacons, ports)
          const RasterOverlayConfig(
            id: 'openseamap',
            urlTemplate: openSeaMapTiles,
            tileSize: 256,
            opacity: 1.0,
            maxZoom: 18.0,
          ),
        ];
    }
  }
  
  /// Check if background requires raster overlays
  bool hasOverlays(MapBackground background) {
    return getOverlays(background).isNotEmpty;
  }
}
