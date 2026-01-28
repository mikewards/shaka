import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../models/ocean_layer.dart';

/// Service for interacting with Copernicus Marine WMTS
class CopernicusWMTSService {
  static const String _baseUrl = 'https://wmts.marine.copernicus.eu/teroWmts';

  final Dio _dio;

  CopernicusWMTSService({Dio? dio}) : _dio = dio ?? Dio();

  /// Build a WMTS tile URL for flutter_map
  /// 
  /// The URL template uses {z}, {x}, {y} placeholders that flutter_map replaces
  static String buildTileUrlTemplate({
    required String layer,
    required String style,
    String? time,
    String projection = 'EPSG:3857',
  }) {
    final timeParam = time != null ? '&time=$time' : '';
    return '$_baseUrl'
        '?service=WMTS'
        '&version=1.0.0'
        '&request=GetTile'
        '&layer=$layer'
        '&tilematrixset=$projection'
        '&tilematrix={z}'
        '&tilerow={y}'
        '&tilecol={x}'
        '&format=image/png'
        '&STYLE=$style'
        '$timeParam';
  }

  /// Build tile URL template for an OceanLayer
  static String buildLayerTileUrl(OceanLayer layer, {String? time}) {
    return buildTileUrlTemplate(
      layer: layer.wmtsLayer,
      style: layer.style,
      time: time,
    );
  }

  /// Get feature info (actual data value) at a specific point
  Future<FeatureInfo?> getFeatureInfo({
    required OceanLayer layer,
    required LatLng point,
    String? time,
    int zoom = 8,
  }) async {
    try {
      // Calculate tile coordinates for EPSG:4326
      final tileCoords = _latLngToTile(point, zoom);
      final pixelCoords = _latLngToPixelInTile(point, zoom, tileCoords);

      final url = '$_baseUrl'
          '?service=WMTS'
          '&version=1.0.0'
          '&request=GetFeatureInfo'
          '&layer=${layer.wmtsLayer}'
          '&tilematrixset=EPSG:4326'
          '&tilematrix=$zoom'
          '&tilerow=${tileCoords.y}'
          '&tilecol=${tileCoords.x}'
          '&i=${pixelCoords.x}'
          '&j=${pixelCoords.y}'
          '&INFOFORMAT=application/json'
          '${time != null ? '&time=$time' : ''}';

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        return FeatureInfo.fromJson(response.data, layer);
      }
    } catch (e) {
      print('GetFeatureInfo error: $e');
    }
    return null;
  }

  /// Convert lat/lng to tile coordinates
  TileCoords _latLngToTile(LatLng point, int zoom) {
    // For EPSG:4326, tiles cover 180°/2^zoom per tile
    final tilesPerRow = 2 << zoom; // 2^(zoom+1) tiles horizontally
    final tilesPerCol = 1 << zoom; // 2^zoom tiles vertically

    final tileWidth = 360.0 / tilesPerRow;
    final tileHeight = 180.0 / tilesPerCol;

    final x = ((point.longitude + 180.0) / tileWidth).floor();
    final y = ((90.0 - point.latitude) / tileHeight).floor();

    return TileCoords(x.clamp(0, tilesPerRow - 1), y.clamp(0, tilesPerCol - 1));
  }

  /// Convert lat/lng to pixel coordinates within a tile
  PixelCoords _latLngToPixelInTile(LatLng point, int zoom, TileCoords tile) {
    final tilesPerRow = 2 << zoom;
    final tilesPerCol = 1 << zoom;

    final tileWidth = 360.0 / tilesPerRow;
    final tileHeight = 180.0 / tilesPerCol;

    final tileLonMin = -180.0 + tile.x * tileWidth;
    final tileLatMax = 90.0 - tile.y * tileHeight;

    final x = ((point.longitude - tileLonMin) / tileWidth * 256).round();
    final y = ((tileLatMax - point.latitude) / tileHeight * 256).round();

    return PixelCoords(x.clamp(0, 255), y.clamp(0, 255));
  }

  /// Get the legend URL for a layer
  static String getLegendUrl(OceanLayer layer) {
    return '$_baseUrl'
        '?SERVICE=WMTS'
        '&REQUEST=GetLegend'
        '&LAYER=${layer.wmtsLayer}'
        '&STYLE=${layer.style}';
  }

  /// Format a DateTime for WMTS time parameter
  static String formatTime(DateTime date) {
    return '${date.toUtc().toIso8601String().split('.')[0]}Z';
  }
}

/// Tile coordinates
class TileCoords {
  final int x;
  final int y;
  const TileCoords(this.x, this.y);
}

/// Pixel coordinates within a tile
class PixelCoords {
  final int x;
  final int y;
  const PixelCoords(this.x, this.y);
}

/// Feature info response from GetFeatureInfo
class FeatureInfo {
  final double? value;
  final String? units;
  final OceanLayer layer;
  final LatLng? location;
  final DateTime? time;

  const FeatureInfo({
    this.value,
    this.units,
    required this.layer,
    this.location,
    this.time,
  });

  factory FeatureInfo.fromJson(dynamic json, OceanLayer layer) {
    double? value;
    String? units;

    try {
      if (json is Map) {
        // Try to extract value from various response formats
        if (json.containsKey('features') && json['features'] is List) {
          final features = json['features'] as List;
          if (features.isNotEmpty) {
            final props = features[0]['properties'];
            if (props != null) {
              value = (props['value'] as num?)?.toDouble();
              units = props['units'] as String?;
            }
          }
        } else if (json.containsKey('value')) {
          value = (json['value'] as num?)?.toDouble();
          units = json['units'] as String?;
        }
      }
    } catch (e) {
      print('Error parsing FeatureInfo: $e');
    }

    return FeatureInfo(
      value: value,
      units: units ?? layer.unit,
      layer: layer,
    );
  }

  /// Format the value for display
  String get displayValue {
    if (value == null) return 'N/A';

    switch (layer.id) {
      case 'sst':
        // Convert Celsius to Fahrenheit
        final fahrenheit = value! * 9 / 5 + 32;
        return '${fahrenheit.toStringAsFixed(1)}°F';
      case 'chl':
        return '${value!.toStringAsFixed(3)} mg/m³';
      case 'zsd':
        return '${value!.toStringAsFixed(1)}m';
      case 'ssh':
        return '${(value! * 100).toStringAsFixed(1)}cm';
      case 'cur':
        return '${value!.toStringAsFixed(2)} m/s';
      default:
        return '${value!.toStringAsFixed(2)} ${units ?? ''}';
    }
  }

  bool get hasValue => value != null;
}
