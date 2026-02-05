import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Detected location from IP geolocation
class IpLocation {
  final double lat;
  final double lon;
  final String? city;
  final String? region;
  final String? country;

  const IpLocation({
    required this.lat,
    required this.lon,
    this.city,
    this.region,
    this.country,
  });

  factory IpLocation.fromJson(Map<String, dynamic> json) {
    return IpLocation(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      city: json['city'] as String?,
      region: json['regionName'] as String?,
      country: json['country'] as String?,
    );
  }

  @override
  String toString() => 'IpLocation($lat, $lon, $city, $region, $country)';
}

/// Singleton service for IP-based geolocation
/// Fetches once on app startup, caches result for session duration
/// Extends ChangeNotifier so screens can listen for when location becomes available
class IpGeolocationService extends ChangeNotifier {
  // Singleton instance
  static final IpGeolocationService _instance = IpGeolocationService._internal();
  factory IpGeolocationService() => _instance;
  IpGeolocationService._internal();

  // Cached result (null = not fetched yet or failed)
  IpLocation? _cachedLocation;
  bool _hasFetched = false;

  /// Get cached location (null if not yet fetched or failed)
  IpLocation? get location => _cachedLocation;

  /// Whether fetch has completed (success or failure)
  bool get hasFetched => _hasFetched;

  /// Fetch IP geolocation from ip-api.com
  /// Call this once on app startup. Result is cached.
  /// Returns null on failure (network error, timeout, parse error).
  Future<IpLocation?> fetchLocation() async {
    // Return cached result if already fetched
    if (_hasFetched) {
      return _cachedLocation;
    }

    try {
      debugPrint('IpGeolocation: Fetching location from ip-api.com...');
      
      final response = await http.get(
        Uri.parse('http://ip-api.com/json'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Check for success status
        if (json['status'] == 'success') {
          _cachedLocation = IpLocation.fromJson(json);
          debugPrint('IpGeolocation: Success - $_cachedLocation');
        } else {
          debugPrint('IpGeolocation: API returned failure status');
        }
      } else {
        debugPrint('IpGeolocation: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('IpGeolocation: Error - $e');
    }

    _hasFetched = true;
    notifyListeners(); // Notify listeners that fetch completed
    return _cachedLocation;
  }
}
