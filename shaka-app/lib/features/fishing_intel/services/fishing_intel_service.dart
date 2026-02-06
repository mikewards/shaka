import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fishing_intel_models.dart';

class FishingIntelService {
  static const _baseUrl = 'https://shaka-api.up.railway.app';
  
  Future<FishingIntelResponse> getSpotIntel(String spotId, {String since = '72h'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/v1/spots/$spotId/intel?since=$since'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));
    
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return FishingIntelResponse.fromJson(json);
    } else if (response.statusCode == 404) {
      // No intel available for this spot
      return FishingIntelResponse(
        spotId: spotId,
        highlights: [],
        speciesSummary: [],
        baitStatus: [],
        sourcesUsed: [],
        dataFreshness: DateTime.now().toIso8601String(),
      );
    } else {
      throw Exception('Failed to load fishing intel: ${response.statusCode}');
    }
  }
}
