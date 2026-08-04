import 'package:flutter/foundation.dart';
import '../api/shaka_api_client.dart';
import '../models/spot_models.dart';

/// Process-wide cache for near-real-time wind readings.
///
/// Every surface that shows "current wind" for a spot (list/preview spot
/// cards, the detail conditions row, the swell compass) reads through this
/// service, so they all render THE SAME reading instead of a mix of live and
/// snapshot values. Entries expire after [_ttl], slightly inside the server's
/// 15-minute bucket cache so a fresh app fetch never outlives the bucket.
class LiveWindService {
  LiveWindService._();

  static final LiveWindService instance = LiveWindService._();

  static const _ttl = Duration(minutes: 10);

  /// Swappable for tests.
  ShakaApiClient client = ShakaApiClient();

  final Map<String, _Entry> _cache = {};
  final Map<String, Future<LiveWind?>> _inFlight = {};

  /// Cached reading if still fresh; never triggers a fetch.
  LiveWind? peek(String spotId) {
    final e = _cache[spotId];
    if (e == null || DateTime.now().difference(e.at) > _ttl) return null;
    return e.wind;
  }

  /// Near-real-time wind for a spot, deduped and cached. Resolves to null
  /// when the reading is unavailable (callers fall back to the snapshot).
  Future<LiveWind?> get(String spotId) {
    final cached = peek(spotId);
    if (cached != null) return Future.value(cached);
    return _inFlight[spotId] ??= _fetch(spotId);
  }

  /// Seed a reading directly (tests only) so widgets resolve it without I/O.
  @visibleForTesting
  void debugSeed(String spotId, LiveWind wind) {
    _cache[spotId] = _Entry(wind, DateTime.now());
  }

  @visibleForTesting
  void debugClear() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<LiveWind?> _fetch(String spotId) async {
    try {
      final wind = await client.getLiveWind(spotId);
      if (wind != null) _cache[spotId] = _Entry(wind, DateTime.now());
      return wind;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(spotId);
    }
  }
}

class _Entry {
  final LiveWind wind;
  final DateTime at;
  _Entry(this.wind, this.at);
}
