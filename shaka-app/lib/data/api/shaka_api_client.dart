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
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
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
    int radiusKm = 50,
  }) async {
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
      return SearchResponse.fromJson(response.data);
    } on DioException catch (e) {
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

  Exception _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timeout. Please check your internet.');
      case DioExceptionType.connectionError:
        return Exception('Cannot connect to server. Please try again later.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['error'] ?? 'Unknown error';
        return Exception('Error ($statusCode): $message');
      default:
        return Exception('Something went wrong. Please try again.');
    }
  }
}
