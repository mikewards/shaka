import 'package:dio/dio.dart';
import '../models/spot_models.dart';

/// API client for Shaka backend
class ShakaApiClient {
  final Dio _dio;
  
  // Production API on Railway
  static const String baseUrl = 'https://shaka-production.up.railway.app/v1';

  ShakaApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ));

  /// Search for spots near a location
  Future<SearchResponse> searchSpots({
    required double lat,
    required double lon,
    required String date,
    int radiusKm = 160,  // ~100 miles
  }) async {
    final stopwatch = Stopwatch()..start();
    print('🌊 API: Searching spots at ($lat, $lon) radius=$radiusKm date=$date');
    try {
      final response = await _dio.get(
        '/spots/search',
        queryParameters: {
          'lat': lat,
          'lon': lon,
          'radius': radiusKm,
          'date': date,
        },
      );
      stopwatch.stop();
      print('✅ API: Search completed in ${stopwatch.elapsedMilliseconds}ms');
      return SearchResponse.fromJson(response.data);
    } on DioException catch (e) {
      stopwatch.stop();
      print('❌ API: Search failed after ${stopwatch.elapsedMilliseconds}ms - ${e.type}: ${e.message}');
      throw _handleError(e);
    }
  }

  /// Get detailed information for a spot
  Future<SpotDetail> getSpotDetail({
    required String spotId,
    required String date,
  }) async {
    try {
      final response = await _dio.get(
        '/spots/$spotId',
        queryParameters: {'date': date},
      );
      return SpotDetail.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get forecast for a spot
  Future<List<DayForecast>> getForecast({
    required String spotId,
    int days = 7,
  }) async {
    try {
      final response = await _dio.get(
        '/forecast/$spotId',
        queryParameters: {'days': days},
      );
      return (response.data as List)
          .map((e) => DayForecast.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get community reports for a region
  Future<List<CommunityReport>> getCommunityReports(String region) async {
    try {
      final response = await _dio.get('/reports/$region');
      return (response.data as List)
          .map((e) => CommunityReport.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Batch fetch spots by IDs (for favorites/home screen)
  Future<BatchSpotsResponse> getSpotsBatch({
    required List<String> spotIds,
    required String date,
  }) async {
    if (spotIds.isEmpty) {
      return BatchSpotsResponse(
        spots: [],
        date: date,
        fetchedAt: DateTime.now().toIso8601String(),
      );
    }
    
    try {
      final response = await _dio.get(
        '/spots/batch',
        queryParameters: {
          'ids': spotIds.join(','),
          'date': date,
        },
      );
      return BatchSpotsResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Search spots by name (for type-ahead search)
  Future<List<SpotSearchResult>> searchSpotsByName({
    required String query,
    int limit = 20,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }
    
    try {
      final response = await _dio.get(
        '/spots/search/name',
        queryParameters: {
          'q': query,
          'limit': limit,
        },
      );
      return (response.data as List)
          .map((e) => SpotSearchResult.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get all regions (for search autocomplete)
  Future<List<RegionInfo>> getRegions() async {
    try {
      final response = await _dio.get('/regions');
      return (response.data as List)
          .map((e) => RegionInfo.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get detailed health status of external services
  /// Used for auto-degradation when services are down
  Future<ServiceHealth> getServiceHealth() async {
    try {
      final response = await _dio.get('/health/detailed');
      return ServiceHealth.fromJson(response.data);
    } catch (e) {
      // If health check fails, assume healthy - don't degrade UI
      // just because we can't reach the health endpoint
      return ServiceHealth.healthy();
    }
  }

  Exception _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timed out.');
      case DioExceptionType.connectionError:
        return Exception('Unable to connect.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['error'] ?? 'Unknown error';
        return Exception('Error $statusCode: $message');
      default:
        return Exception('Request failed.');
    }
  }
}
