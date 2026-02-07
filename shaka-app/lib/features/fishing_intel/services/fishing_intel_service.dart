import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fishing_intel_models.dart';

class FishingIntelService {
  static const _baseUrl = 'https://shaka-production.up.railway.app';
  
  Future<FishingIntelResponse> getSpotIntel(String spotId, {String since = '72h', int? tzOffset}) async {
    final params = <String, String>{'since': since};
    if (tzOffset != null) params['tzOffset'] = tzOffset.toString();
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await http.get(
      Uri.parse('$_baseUrl/v1/spots/$spotId/intel?$query'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return FishingIntelResponse.fromJson(json);
    } else if (response.statusCode == 404) {
      // No intel available for this spot
      return FishingIntelResponse(
        spotId: spotId,
        headline: null,
        hotSpecies: [],
        coldSpecies: [],
        recentCatches: [],
        sourcesUsed: [],
        dataFreshness: DateTime.now().toIso8601String(),
        totalReports: 0,
        narrativeInsights: [],
      );
    } else {
      throw Exception('Failed to load fishing intel: ${response.statusCode}');
    }
  }

  /// Regional fishing report (e.g. SoCal). No spot; data filtered by sources.regional_report.
  Future<FishingIntelResponse> getRegionIntel(String regionId, {String since = '72h', int? tzOffset}) async {
    final params = <String, String>{'since': since};
    if (tzOffset != null) params['tzOffset'] = tzOffset.toString();
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await http.get(
      Uri.parse('$_baseUrl/v1/regions/$regionId/intel?$query'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return FishingIntelResponse.fromJson(json);
    } else if (response.statusCode == 404) {
      return FishingIntelResponse(
        spotId: regionId,
        headline: null,
        hotSpecies: [],
        coldSpecies: [],
        recentCatches: [],
        sourcesUsed: [],
        dataFreshness: DateTime.now().toIso8601String(),
        totalReports: 0,
        narrativeInsights: [],
      );
    } else {
      throw Exception('Failed to load region intel: ${response.statusCode}');
    }
  }
}
