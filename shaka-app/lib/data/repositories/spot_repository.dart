import '../api/shaka_api_client.dart';
import '../models/spot_models.dart';

/// Repository for spot data operations
class SpotRepository {
  final ShakaApiClient _apiClient;

  SpotRepository(this._apiClient);

  /// Search for spots near a location
  Future<SearchResponse> searchSpots({
    required double lat,
    required double lon,
    required String date,
    int radiusKm = 50,
  }) async {
    return _apiClient.searchSpots(
      lat: lat,
      lon: lon,
      date: date,
      radiusKm: radiusKm,
    );
  }

  /// Get detailed information for a spot
  Future<SpotDetail> getSpotDetail({
    required String spotId,
    required String date,
  }) async {
    return _apiClient.getSpotDetail(
      spotId: spotId,
      date: date,
    );
  }

  /// Get forecast for a spot
  Future<List<DayForecast>> getForecast({
    required String spotId,
    int days = 7,
  }) async {
    return _apiClient.getForecast(
      spotId: spotId,
      days: days,
    );
  }

  /// Get community reports
  Future<List<CommunityReport>> getCommunityReports(String region) async {
    return _apiClient.getCommunityReports(region);
  }
}
