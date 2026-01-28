/// Data models for spearfishing spots

class Coordinates {
  final double lat;
  final double lon;

  const Coordinates({required this.lat, required this.lon});

  factory Coordinates.fromJson(Map<String, dynamic> json) {
    return Coordinates(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
}

class SpotConditions {
  final String visibility;
  final String waterTemp;
  final String swell;
  final String wind;
  final String tideState;
  final String currentStrength;

  const SpotConditions({
    required this.visibility,
    required this.waterTemp,
    required this.swell,
    required this.wind,
    this.tideState = '',
    this.currentStrength = '',
  });

  factory SpotConditions.fromJson(Map<String, dynamic> json) {
    return SpotConditions(
      visibility: json['visibility'] ?? '',
      waterTemp: json['waterTemp'] ?? '',
      swell: json['swell'] ?? '',
      wind: json['wind'] ?? '',
      tideState: json['tideState'] ?? '',
      currentStrength: json['currentStrength'] ?? '',
    );
  }
}

class ScoreBreakdown {
  final int visibility;
  final int weather;
  final int swell;
  final int fishActivity;
  final int accessibility;
  final int safety;

  const ScoreBreakdown({
    required this.visibility,
    required this.weather,
    required this.swell,
    required this.fishActivity,
    required this.accessibility,
    required this.safety,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) {
    return ScoreBreakdown(
      visibility: json['visibility'] ?? 0,
      weather: json['weather'] ?? 0,
      swell: json['swell'] ?? 0,
      fishActivity: json['fishActivity'] ?? 0,
      accessibility: json['accessibility'] ?? 0,
      safety: json['safety'] ?? 0,
    );
  }
}

class ShakaScore {
  final int overall;
  final int confidence;
  final ScoreBreakdown breakdown;

  const ShakaScore({
    required this.overall,
    required this.confidence,
    required this.breakdown,
  });

  factory ShakaScore.fromJson(Map<String, dynamic> json) {
    return ShakaScore(
      overall: json['overall'] ?? 0,
      confidence: json['confidence'] ?? 0,
      breakdown: ScoreBreakdown.fromJson(json['breakdown'] ?? {}),
    );
  }
}

class SpotSummary {
  final String id;
  final String name;
  final Coordinates coordinates;
  final int shakaScore;
  final int confidence;
  final String access;
  final SpotConditions conditions;
  final List<String> expectedFish;
  final List<String> gearRecommendations;
  final List<String> risks;
  final String bestTimeOfDay;

  const SpotSummary({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.shakaScore,
    required this.confidence,
    required this.access,
    required this.conditions,
    required this.expectedFish,
    required this.gearRecommendations,
    required this.risks,
    required this.bestTimeOfDay,
  });

  factory SpotSummary.fromJson(Map<String, dynamic> json) {
    return SpotSummary(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      coordinates: Coordinates.fromJson(json['coordinates'] ?? {}),
      shakaScore: json['shakaScore'] ?? 0,
      confidence: json['confidence'] ?? 0,
      access: json['access'] ?? 'shore',
      conditions: SpotConditions.fromJson(json['conditions'] ?? {}),
      expectedFish: List<String>.from(json['expectedFish'] ?? []),
      gearRecommendations: List<String>.from(json['gearRecommendations'] ?? []),
      risks: List<String>.from(json['risks'] ?? []),
      bestTimeOfDay: json['bestTimeOfDay'] ?? '',
    );
  }
}

class AccessInfo {
  final String type;
  final String directions;
  final String parkingInfo;
  final bool permitRequired;
  final bool boatLaunchNearby;

  const AccessInfo({
    required this.type,
    required this.directions,
    required this.parkingInfo,
    this.permitRequired = false,
    this.boatLaunchNearby = false,
  });

  factory AccessInfo.fromJson(Map<String, dynamic> json) {
    return AccessInfo(
      type: json['type'] ?? '',
      directions: json['directions'] ?? '',
      parkingInfo: json['parkingInfo'] ?? '',
      permitRequired: json['permitRequired'] ?? false,
      boatLaunchNearby: json['boatLaunchNearby'] ?? false,
    );
  }
}

class FishInfo {
  final String name;
  final String? localName;
  final String likelihood;
  final String? seasonalNotes;

  const FishInfo({
    required this.name,
    this.localName,
    required this.likelihood,
    this.seasonalNotes,
  });

  factory FishInfo.fromJson(Map<String, dynamic> json) {
    return FishInfo(
      name: json['name'] ?? '',
      localName: json['localName'],
      likelihood: json['likelihood'] ?? 'possible',
      seasonalNotes: json['seasonalNotes'],
    );
  }
}

class GearItem {
  final String item;
  final String reason;
  final bool essential;

  const GearItem({
    required this.item,
    required this.reason,
    this.essential = false,
  });

  factory GearItem.fromJson(Map<String, dynamic> json) {
    return GearItem(
      item: json['item'] ?? '',
      reason: json['reason'] ?? '',
      essential: json['essential'] ?? false,
    );
  }
}

class RiskInfo {
  final String risk;
  final String severity;
  final String mitigation;

  const RiskInfo({
    required this.risk,
    required this.severity,
    required this.mitigation,
  });

  factory RiskInfo.fromJson(Map<String, dynamic> json) {
    return RiskInfo(
      risk: json['risk'] ?? '',
      severity: json['severity'] ?? 'low',
      mitigation: json['mitigation'] ?? '',
    );
  }
}

class DayForecast {
  final String date;
  final int shakaScore;
  final int confidence;
  final SpotConditions conditions;

  const DayForecast({
    required this.date,
    required this.shakaScore,
    required this.confidence,
    required this.conditions,
  });

  factory DayForecast.fromJson(Map<String, dynamic> json) {
    return DayForecast(
      date: json['date'] ?? '',
      shakaScore: json['shakaScore'] ?? 0,
      confidence: json['confidence'] ?? 0,
      conditions: SpotConditions.fromJson(json['conditions'] ?? {}),
    );
  }
}

class CommunityReport {
  final String source;
  final String date;
  final String summary;
  final String? url;

  const CommunityReport({
    required this.source,
    required this.date,
    required this.summary,
    this.url,
  });

  factory CommunityReport.fromJson(Map<String, dynamic> json) {
    return CommunityReport(
      source: json['source'] ?? '',
      date: json['date'] ?? '',
      summary: json['summary'] ?? '',
      url: json['url'],
    );
  }
}

class SpotDetail {
  final String id;
  final String name;
  final String description;
  final Coordinates coordinates;
  final ShakaScore score;
  final AccessInfo access;
  final SpotConditions conditions;
  final List<DayForecast> forecast;
  final List<FishInfo> expectedFish;
  final List<GearItem> gearRecommendations;
  final List<RiskInfo> risks;
  final List<CommunityReport> communityReports;
  final String bestTimeOfDay;
  final String? imageUrl;

  const SpotDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.coordinates,
    required this.score,
    required this.access,
    required this.conditions,
    required this.forecast,
    required this.expectedFish,
    required this.gearRecommendations,
    required this.risks,
    required this.communityReports,
    required this.bestTimeOfDay,
    this.imageUrl,
  });

  factory SpotDetail.fromJson(Map<String, dynamic> json) {
    return SpotDetail(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      coordinates: Coordinates.fromJson(json['coordinates'] ?? {}),
      score: ShakaScore.fromJson(json['score'] ?? {}),
      access: AccessInfo.fromJson(json['access'] ?? {}),
      conditions: SpotConditions.fromJson(json['conditions'] ?? {}),
      forecast: (json['forecast'] as List? ?? [])
          .map((e) => DayForecast.fromJson(e))
          .toList(),
      expectedFish: (json['expectedFish'] as List? ?? [])
          .map((e) => FishInfo.fromJson(e))
          .toList(),
      gearRecommendations: (json['gearRecommendations'] as List? ?? [])
          .map((e) => GearItem.fromJson(e))
          .toList(),
      risks: (json['risks'] as List? ?? [])
          .map((e) => RiskInfo.fromJson(e))
          .toList(),
      communityReports: (json['communityReports'] as List? ?? [])
          .map((e) => CommunityReport.fromJson(e))
          .toList(),
      bestTimeOfDay: json['bestTimeOfDay'] ?? '',
      imageUrl: json['imageUrl'],
    );
  }
}

class SearchResponse {
  final List<SpotSummary> spots;
  final Coordinates searchCenter;
  final int radiusKm;
  final String date;

  const SearchResponse({
    required this.spots,
    required this.searchCenter,
    required this.radiusKm,
    required this.date,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    return SearchResponse(
      spots: (json['spots'] as List? ?? [])
          .map((e) => SpotSummary.fromJson(e))
          .toList(),
      searchCenter: Coordinates.fromJson(json['searchCenter'] ?? {}),
      radiusKm: json['radiusKm'] ?? 50,
      date: json['date'] ?? '',
    );
  }
}
