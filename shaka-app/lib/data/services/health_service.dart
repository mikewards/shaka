import 'package:flutter/foundation.dart';
import '../api/shaka_api_client.dart';
import '../models/spot_models.dart';

/// Singleton service to track external service health.
/// Automatically fetches health on first access and caches for 5 minutes.
/// UI components can check this to auto-degrade features.
class HealthProvider extends ChangeNotifier {
  static final HealthProvider _instance = HealthProvider._internal();
  factory HealthProvider() => _instance;
  HealthProvider._internal();

  final ShakaApiClient _api = ShakaApiClient();
  
  // ALWAYS assume healthy - only show degraded if we have CONFIRMED evidence
  // The health endpoint is optional and services work fine without it
  ServiceHealth _health = ServiceHealth.healthy();
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isFetching = false;

  static const Duration _cacheTimeout = Duration(minutes: 5);

  /// Current health status
  ServiceHealth get health => _health;

  /// Whether GIBS satellite imagery is available
  bool get isGibsAvailable => _health.isGibsAvailable;

  /// Whether Copernicus ocean data is available
  bool get isCopernicusAvailable => _health.isCopernicusAvailable;

  /// Whether weather data is available
  bool get isWeatherAvailable => _health.isOpenMeteoAvailable;

  /// Whether any service is degraded
  bool get isDegraded => _health.isDegraded || _health.isUnhealthy;

  /// Fetch health status from backend (with caching)
  Future<ServiceHealth> fetchHealth({bool force = false}) async {
    final now = DateTime.now();
    
    // Return cached if still valid
    if (!force && now.difference(_lastFetch) < _cacheTimeout) {
      return _health;
    }

    // Avoid concurrent fetches
    if (_isFetching) {
      return _health;
    }

    _isFetching = true;
    try {
      _health = await _api.getServiceHealth();
      _lastFetch = now;
      notifyListeners();
      
      // Log any degraded services
      if (_health.isDegraded) {
        final degraded = _health.services.entries
            .where((e) => e.value.isError)
            .map((e) => e.key)
            .join(', ');
        debugPrint('Service health degraded: $degraded');
      }
    } catch (e) {
      // If health check fails, KEEP assuming healthy
      // Don't degrade the UI just because we can't reach the health endpoint
      // The actual services may still be working fine
      debugPrint('Health check failed (keeping healthy state): $e');
    } finally {
      _isFetching = false;
    }

    return _health;
  }

  /// Check health in background (call on app startup)
  void checkHealthInBackground() {
    fetchHealth().catchError((_) {
      // Ignore errors - health is already set to degraded
      return _health;
    });
  }
}
