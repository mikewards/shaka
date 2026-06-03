import 'package:flutter/foundation.dart';

/// Detected location (kept as a type for the screens that reference it).
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

  @override
  String toString() => 'IpLocation($lat, $lon, $city, $region, $country)';
}

/// IP-based geolocation has been removed for privacy: Shaka no longer contacts
/// any third-party IP-location service (previously ip-api.com). All location
/// comes from the user's explicit Map Home and saved-spot choices.
///
/// This singleton is retained so existing screens that read [location] keep
/// compiling; [location] now always returns null.
class IpGeolocationService extends ChangeNotifier {
  static final IpGeolocationService _instance =
      IpGeolocationService._internal();
  factory IpGeolocationService() => _instance;
  IpGeolocationService._internal();

  /// Always null — no IP geolocation is performed.
  IpLocation? get location => null;

  /// Always true — there is nothing to fetch.
  bool get hasFetched => true;
}
