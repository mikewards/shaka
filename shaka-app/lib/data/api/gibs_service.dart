import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/gibs_layer.dart';

/// Service for building NASA GIBS WMTS tile URLs
/// Includes self-healing: auto-hides unavailable layers
class GibsService {
  /// Cache of layer availability status (layerId -> isAvailable)
  /// Checked once per app session, cached to avoid repeated requests
  static final Map<String, bool> _availabilityCache = {};
  static DateTime? _lastAvailabilityCheck;
  /// GIBS WMTS base URL for Web Mercator (EPSG:3857) - compatible with MapLibre
  static const _baseUrl = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best';

  /// Get yesterday's date in UTC (GIBS data typically lags by ~1 day)
  static DateTime get yesterdayUtc {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day - 1);
  }

  /// Format date for GIBS API (YYYY-MM-DD)
  static String formatDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Build WMTS tile URL for a GIBS layer
  ///
  /// For Web Mercator (EPSG:3857), GIBS uses GoogleMapsCompatible tile matrix sets:
  /// - GoogleMapsCompatible_Level6 through GoogleMapsCompatible_Level12
  /// The level corresponds to max zoom for the layer
  static String buildTileUrlWithFormat(GibsLayer layer, {String? time}) {
    final dateStr = time ?? formatDate(yesterdayUtc);
    final tileMatrixSet = _getTileMatrixSet(layer.maxZoom);
    final format = layer.format;

    // GIBS WMTS URL pattern with {z}/{y}/{x} placeholders for MapLibre (Web Mercator)
    return '$_baseUrl/${layer.id}/default/$dateStr/$tileMatrixSet/{z}/{y}/{x}.$format';
  }

  /// Build a direct tile URL (for testing or single tile fetch)
  static String buildDirectTileUrl(
    GibsLayer layer, {
    String? time,
    required int z,
    required int y,
    required int x,
  }) {
    final dateStr = time ?? formatDate(yesterdayUtc);
    final tileMatrixSet = _getTileMatrixSet(layer.maxZoom);
    final format = layer.format;

    return '$_baseUrl/${layer.id}/default/$dateStr/$tileMatrixSet/$z/$y/$x.$format';
  }

  /// Build WMTS URL for orbit track vector tiles
  /// Orbit tracks are vector tiles (.mvt) at Level6
  /// Returns null if the layer doesn't have orbit track data
  static String? buildOrbitTrackUrl(GibsLayer layer, {String? time, bool ascending = true}) {
    final trackLayerId = ascending ? layer.orbitTrackAscending : layer.orbitTrackDescending;
    if (trackLayerId == null) return null;
    
    final dateStr = time ?? formatDate(yesterdayUtc);
    // Orbit tracks use GoogleMapsCompatible_Level6
    return '$_baseUrl/$trackLayerId/default/$dateStr/GoogleMapsCompatible_Level6/{z}/{y}/{x}.mvt';
  }

  /// Get the appropriate tile matrix set for Web Mercator based on max zoom level
  /// GIBS uses GoogleMapsCompatible_Level{N} for EPSG:3857
  static String _getTileMatrixSet(int maxZoom) {
    // GIBS offers levels from 6 to 12 typically
    // Clamp to valid range
    final level = maxZoom.clamp(6, 12);
    return 'GoogleMapsCompatible_Level$level';
  }

  /// Get available date range for GIBS data
  /// Most GIBS products have data from around 2012 to present
  static DateTimeRange get availableDateRange {
    return DateTimeRange(
      start: DateTime(2012, 5, 8), // VIIRS SNPP launch date
      end: DateTime.now(),
    );
  }

  /// Check if a date is valid for GIBS data (general check)
  static bool isValidDate(DateTime date) {
    final range = availableDateRange;
    return date.isAfter(range.start) && date.isBefore(range.end.add(const Duration(days: 1)));
  }
  
  /// Check if a date is valid for a specific layer
  /// Returns true if date is within the layer's data availability range
  static bool isDateValidForLayer(GibsLayer layer, DateTime date) {
    // Check if date is not in the future
    final now = DateTime.now().toUtc();
    if (date.isAfter(now)) return false;
    
    // Check if layer has a start date and date is after it
    if (layer.dataStartDate != null) {
      if (date.isBefore(layer.dataStartDate!)) return false;
    }
    
    return true;
  }
  
  /// Get a message describing why a date might be invalid for a layer
  static String? getDateValidationMessage(GibsLayer layer, DateTime date) {
    final now = DateTime.now().toUtc();
    
    if (date.isAfter(now)) {
      return 'Date is in the future. GIBS data is typically available 1-2 days after observation.';
    }
    
    if (layer.dataStartDate != null && date.isBefore(layer.dataStartDate!)) {
      final startStr = formatDate(layer.dataStartDate!);
      return '${layer.satellite ?? layer.shortName} data starts from $startStr. '
             'Please select a more recent date.';
    }
    
    return null;
  }
  
  /// Get satellite overpass time information for display
  static String? getOverpassTimeInfo(GibsLayer layer) {
    if (layer.equatorCrossingTime == null) return null;
    
    return 'Typical overpass: ${layer.equatorCrossingTime}';
  }

  /// Check if a layer is available (makes HEAD request to sample tile)
  /// Results are cached for the app session
  /// Returns true if layer is available, false if deprecated/unavailable
  static Future<bool> isLayerAvailable(GibsLayer layer) async {
    // Return cached result if available
    if (_availabilityCache.containsKey(layer.id)) {
      return _availabilityCache[layer.id]!;
    }
    
    try {
      // Check a sample tile at zoom level 2 (covers whole world, fast to check)
      final url = buildDirectTileUrl(layer, z: 2, y: 1, x: 1);
      final response = await http.head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      
      final isAvailable = response.statusCode == 200;
      _availabilityCache[layer.id] = isAvailable;
      
      if (!isAvailable) {
        debugPrint('GIBS layer ${layer.id} unavailable (${response.statusCode})');
      }
      
      return isAvailable;
    } catch (e) {
      // On error, assume available (don't hide layers due to network issues)
      debugPrint('GIBS layer check failed for ${layer.id}: $e');
      _availabilityCache[layer.id] = true;
      return true;
    }
  }

  /// Check availability of all layers and return only available ones
  /// Call this once on app startup to pre-warm the cache
  static Future<List<GibsLayer>> getAvailableLayers() async {
    final availableLayers = <GibsLayer>[];
    
    // Check all layers in parallel
    final futures = GibsLayer.allLayers.map((layer) async {
      final isAvailable = await isLayerAvailable(layer);
      return isAvailable ? layer : null;
    });
    
    final results = await Future.wait(futures);
    for (final layer in results) {
      if (layer != null) {
        availableLayers.add(layer);
      }
    }
    
    return availableLayers;
  }

  /// Clear the availability cache (e.g., on refresh)
  static void clearAvailabilityCache() {
    _availabilityCache.clear();
    _lastAvailabilityCheck = null;
  }
}
