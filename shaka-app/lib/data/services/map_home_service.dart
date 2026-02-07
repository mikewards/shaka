import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores and retrieves the user's "Map Home" — default center for Explore and Gibs maps.
/// Persisted in Keychain (iOS) / SecureStorage so it survives app restarts.
/// Notifies [mapHomeChanged] when Map Home is set so maps can refresh.
class MapHomeService {
  static const _keyLat = 'map_home_lat';
  static const _keyLon = 'map_home_lon';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Listen to this and call [getMapHome] + animate camera when notified.
  static final ChangeNotifier mapHomeChanged = ChangeNotifier();

  /// Zoom level that shows approximately 200 km radius (used when opening maps at Map Home).
  static const double mapHomeZoom = 6.5;

  /// Whether Map Home has been set (user has completed first-time prompt or set from Profile).
  Future<bool> isMapHomeSet() async {
    final lat = await _storage.read(key: _keyLat);
    return lat != null && lat.isNotEmpty;
  }

  /// Get current Map Home coordinates, or null if not set.
  Future<MapHomeLocation?> getMapHome() async {
    final latStr = await _storage.read(key: _keyLat);
    final lonStr = await _storage.read(key: _keyLon);
    if (latStr == null || lonStr == null) return null;
    final lat = double.tryParse(latStr);
    final lon = double.tryParse(lonStr);
    if (lat == null || lon == null) return null;
    return MapHomeLocation(lat: lat, lon: lon);
  }

  /// Save Map Home. Call after user picks a location (first launch or Profile).
  /// Notifies listeners so Explore and Gibs maps can animate to the new center.
  Future<void> setMapHome(double lat, double lon) async {
    await _storage.write(key: _keyLat, value: lat.toString());
    await _storage.write(key: _keyLon, value: lon.toString());
    mapHomeChanged.notifyListeners();
  }

  /// Clear Map Home (optional; e.g. if user wants to reset).
  Future<void> clearMapHome() async {
    await _storage.delete(key: _keyLat);
    await _storage.delete(key: _keyLon);
  }
}

class MapHomeLocation {
  final double lat;
  final double lon;

  const MapHomeLocation({required this.lat, required this.lon});

  String get displaySubtitle =>
      '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
}
