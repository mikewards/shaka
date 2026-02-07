import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and retrieves the user's "Map Home" — default center for Explore and Gibs maps.
/// Persisted in SharedPreferences; can be set on first launch or from Profile.
/// Notifies [mapHomeChanged] when Map Home is set so maps can refresh.
class MapHomeService {
  static const _keyLat = 'map_home_lat';
  static const _keyLon = 'map_home_lon';

  /// Listen to this and call [getMapHome] + animate camera when notified.
  static final ChangeNotifier mapHomeChanged = ChangeNotifier();

  /// Zoom level that shows approximately 200 km radius (used when opening maps at Map Home).
  static const double mapHomeZoom = 6.5;

  /// Whether Map Home has been set (user has completed first-time prompt or set from Profile).
  Future<bool> isMapHomeSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyLat) && prefs.containsKey(_keyLon);
  }

  /// Get current Map Home coordinates, or null if not set.
  Future<MapHomeLocation?> getMapHome() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLat);
    final lon = prefs.getDouble(_keyLon);
    if (lat == null || lon == null) return null;
    return MapHomeLocation(lat: lat, lon: lon);
  }

  /// Save Map Home. Call after user picks a location (first launch or Profile).
  /// Notifies listeners so Explore and Gibs maps can animate to the new center.
  Future<void> setMapHome(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLat, lat);
    await prefs.setDouble(_keyLon, lon);
    mapHomeChanged.notifyListeners();
  }

  /// Clear Map Home (optional; e.g. if user wants to reset).
  Future<void> clearMapHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLat);
    await prefs.remove(_keyLon);
  }
}

class MapHomeLocation {
  final double lat;
  final double lon;

  const MapHomeLocation({required this.lat, required this.lon});

  String get displaySubtitle =>
      '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
}
