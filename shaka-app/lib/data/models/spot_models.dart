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

  const ScoreBreakdown({
    required this.visibility,
    required this.weather,
    required this.swell,
    required this.fishActivity,
    required this.accessibility,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) {
    return ScoreBreakdown(
      visibility: json['visibility'] ?? 0,
      weather: json['weather'] ?? 0,
      swell: json['swell'] ?? 0,
      fishActivity: json['fishActivity'] ?? 0,
      accessibility: json['accessibility'] ?? 0,
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
  final GibsSatelliteReadings? satelliteReadings;  // Cached satellite data

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
    this.satelliteReadings,
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
      satelliteReadings: json['satelliteReadings'] != null
          ? GibsSatelliteReadings.fromJson(json['satelliteReadings'])
          : null,
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

/// GIBS satellite chlorophyll readings from multiple satellites
class GibsSatelliteReadings {
  final double? paceToday;
  final double? paceYesterday;
  final double? noaa20Today;
  final double? noaa20Yesterday;
  final double? noaa21Today;
  final double? noaa21Yesterday;
  final double? sentinel3aToday;
  final double? sentinel3aYesterday;
  final double? sentinel3bToday;
  final double? sentinel3bYesterday;
  final DateTime? paceObservationTime;
  final DateTime? noaa20ObservationTime;
  final DateTime? noaa21ObservationTime;
  final String? dataDate; // The date "today" refers to
  // NOAA ERDDAP chlorophyll (separate from GIBS imagery)
  final double? noaaErddapChlorophyll;
  final DateTime? noaaErddapFetchTime;

  const GibsSatelliteReadings({
    this.paceToday,
    this.paceYesterday,
    this.noaa20Today,
    this.noaa20Yesterday,
    this.noaa21Today,
    this.noaa21Yesterday,
    this.sentinel3aToday,
    this.sentinel3aYesterday,
    this.sentinel3bToday,
    this.sentinel3bYesterday,
    this.paceObservationTime,
    this.noaa20ObservationTime,
    this.noaa21ObservationTime,
    this.dataDate,
    this.noaaErddapChlorophyll,
    this.noaaErddapFetchTime,
  });

  factory GibsSatelliteReadings.fromJson(Map<String, dynamic> json) {
    return GibsSatelliteReadings(
      paceToday: (json['paceToday'] as num?)?.toDouble(),
      paceYesterday: (json['paceYesterday'] as num?)?.toDouble(),
      noaa20Today: (json['noaa20Today'] as num?)?.toDouble(),
      noaa20Yesterday: (json['noaa20Yesterday'] as num?)?.toDouble(),
      noaa21Today: (json['noaa21Today'] as num?)?.toDouble(),
      noaa21Yesterday: (json['noaa21Yesterday'] as num?)?.toDouble(),
      sentinel3aToday: (json['sentinel3aToday'] as num?)?.toDouble(),
      sentinel3aYesterday: (json['sentinel3aYesterday'] as num?)?.toDouble(),
      sentinel3bToday: (json['sentinel3bToday'] as num?)?.toDouble(),
      sentinel3bYesterday: (json['sentinel3bYesterday'] as num?)?.toDouble(),
      paceObservationTime: json['paceObservationTime'] != null
          ? DateTime.tryParse(json['paceObservationTime'])
          : null,
      noaa20ObservationTime: json['noaa20ObservationTime'] != null
          ? DateTime.tryParse(json['noaa20ObservationTime'])
          : null,
      noaa21ObservationTime: json['noaa21ObservationTime'] != null
          ? DateTime.tryParse(json['noaa21ObservationTime'])
          : null,
      dataDate: json['dataDate'],
      noaaErddapChlorophyll: (json['noaaErddapChlorophyll'] as num?)?.toDouble(),
      noaaErddapFetchTime: json['noaaErddapFetchTime'] != null
          ? DateTime.tryParse(json['noaaErddapFetchTime'])
          : null,
    );
  }

  /// Check if we have any data at all
  bool get hasAnyData =>
      paceToday != null ||
      paceYesterday != null ||
      noaa20Today != null ||
      noaa20Yesterday != null ||
      noaa21Today != null ||
      noaa21Yesterday != null ||
      sentinel3aToday != null ||
      sentinel3aYesterday != null ||
      sentinel3bToday != null ||
      sentinel3bYesterday != null ||
      noaaErddapChlorophyll != null;
}

/// Marine Protected Area status from ProtectedSeas Navigator
class MPAStatus {
  final bool isProtected;
  final String? siteName;
  final String? designation;
  final int spearfishingStatus;  // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
  final int protectionLevel;     // 1-5 Level of Fishing Protection
  final String? speciesOfConcern;
  final String? purpose;
  final String? detailsUrl;

  const MPAStatus({
    required this.isProtected,
    this.siteName,
    this.designation,
    required this.spearfishingStatus,
    required this.protectionLevel,
    this.speciesOfConcern,
    this.purpose,
    this.detailsUrl,
  });

  factory MPAStatus.fromJson(Map<String, dynamic> json) {
    return MPAStatus(
      isProtected: json['isProtected'] ?? false,
      siteName: json['siteName'],
      designation: json['designation'],
      spearfishingStatus: json['spearfishingStatus'] ?? 3,
      protectionLevel: json['protectionLevel'] ?? 0,
      speciesOfConcern: json['speciesOfConcern'],
      purpose: json['purpose'],
      detailsUrl: json['detailsUrl'],
    );
  }
  
  /// Get human-readable spearfishing status
  String get spearfishingStatusText {
    switch (spearfishingStatus) {
      case 0: return 'Allowed';
      case 1: return 'Prohibited';
      case 2: return 'Restricted';
      default: return 'Check regulations';
    }
  }
}

/// Regulatory information for a spot
class RegulationInfo {
  final String regulatoryAgency;
  final String regulationsUrl;
  final String? licensingUrl;
  final String? note;
  final MPAStatus? mpaStatus;

  const RegulationInfo({
    required this.regulatoryAgency,
    required this.regulationsUrl,
    this.licensingUrl,
    this.note,
    this.mpaStatus,
  });

  factory RegulationInfo.fromJson(Map<String, dynamic> json) {
    return RegulationInfo(
      regulatoryAgency: json['regulatoryAgency'] ?? 'Fisheries Authority',
      regulationsUrl: json['regulationsUrl'] ?? 'https://navigatormap.org/',
      licensingUrl: json['licensingUrl'],
      note: json['note'],
      mpaStatus: json['mpaStatus'] != null
          ? MPAStatus.fromJson(json['mpaStatus'])
          : null,
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
  final GibsSatelliteReadings? satelliteReadings;
  final RegulationInfo? regulations;

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
    this.satelliteReadings,
    this.regulations,
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
      satelliteReadings: json['satelliteReadings'] != null
          ? GibsSatelliteReadings.fromJson(json['satelliteReadings'])
          : null,
      regulations: json['regulations'] != null
          ? RegulationInfo.fromJson(json['regulations'])
          : null,
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

/// Result from spot name search (lightweight, no conditions)
class SpotSearchResult {
  final String id;
  final String name;
  final String region;
  final Coordinates coordinates;
  final String access;
  final int shakaScore;

  const SpotSearchResult({
    required this.id,
    required this.name,
    required this.region,
    required this.coordinates,
    required this.access,
    this.shakaScore = 0,
  });

  factory SpotSearchResult.fromJson(Map<String, dynamic> json) {
    return SpotSearchResult(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      region: json['region'] ?? '',
      coordinates: Coordinates.fromJson(json['coordinates'] ?? {}),
      access: json['access'] ?? 'shore',
      shakaScore: json['shakaScore'] ?? json['score'] ?? 0,
    );
  }
}

/// Response from batch spot fetch
class BatchSpotsResponse {
  final List<SpotSummary> spots;
  final String date;
  final String fetchedAt;

  const BatchSpotsResponse({
    required this.spots,
    required this.date,
    required this.fetchedAt,
  });

  factory BatchSpotsResponse.fromJson(Map<String, dynamic> json) {
    return BatchSpotsResponse(
      spots: (json['spots'] as List? ?? [])
          .map((e) => SpotSummary.fromJson(e))
          .toList(),
      date: json['date'] ?? '',
      fetchedAt: json['fetchedAt'] ?? '',
    );
  }
}

/// Region info for search autocomplete
class RegionInfo {
  final String id;
  final String name;
  final int spotCount;
  final double centerLat;
  final double centerLon;

  const RegionInfo({
    required this.id,
    required this.name,
    required this.spotCount,
    this.centerLat = 0.0,
    this.centerLon = 0.0,
  });

  factory RegionInfo.fromJson(Map<String, dynamic> json) {
    return RegionInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      spotCount: json['spotCount'] ?? 0,
      centerLat: (json['centerLat'] ?? json['lat'] ?? 0.0).toDouble(),
      centerLon: (json['centerLon'] ?? json['lon'] ?? 0.0).toDouble(),
    );
  }
}

/// Status of an individual external service
class ExternalServiceStatus {
  final String status; // "ok", "error", "degraded"
  final String? message;
  final String lastChecked;

  const ExternalServiceStatus({
    required this.status,
    this.message,
    required this.lastChecked,
  });

  bool get isOk => status == 'ok';
  bool get isError => status == 'error';

  factory ExternalServiceStatus.fromJson(Map<String, dynamic> json) {
    return ExternalServiceStatus(
      status: json['status'] ?? 'error',
      message: json['message'],
      lastChecked: json['lastChecked'] ?? '',
    );
  }

  factory ExternalServiceStatus.unknown() {
    return ExternalServiceStatus(
      status: 'error',
      message: 'Unable to check',
      lastChecked: DateTime.now().toIso8601String(),
    );
  }
}

/// Health status of all external services
/// Used by app to auto-degrade features when services are unavailable
class ServiceHealth {
  final String status; // "healthy", "degraded", "unhealthy"
  final Map<String, ExternalServiceStatus> services;
  final String timestamp;

  const ServiceHealth({
    required this.status,
    required this.services,
    required this.timestamp,
  });

  bool get isHealthy => status == 'healthy';
  bool get isDegraded => status == 'degraded';
  bool get isUnhealthy => status == 'unhealthy';

  /// Check if a specific service is available
  bool isServiceAvailable(String serviceName) {
    return services[serviceName]?.isOk ?? false;
  }

  /// Check if GIBS satellite imagery is available
  bool get isGibsAvailable => isServiceAvailable('gibs');

  /// Check if Copernicus ocean data is available
  bool get isCopernicusAvailable => isServiceAvailable('copernicus');

  /// Check if OpenMeteo weather is available
  bool get isOpenMeteoAvailable => isServiceAvailable('openmeteo');

  /// Check if NOAA data is available
  bool get isNoaaAvailable => isServiceAvailable('noaa');

  factory ServiceHealth.fromJson(Map<String, dynamic> json) {
    final servicesJson = json['services'] as Map<String, dynamic>? ?? {};
    final services = servicesJson.map((key, value) => MapEntry(
      key,
      ExternalServiceStatus.fromJson(value as Map<String, dynamic>),
    ));

    return ServiceHealth(
      status: json['status'] ?? 'degraded',
      services: services,
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
    );
  }

  /// Create a degraded health status when unable to reach health endpoint
  factory ServiceHealth.degraded() {
    return ServiceHealth(
      status: 'degraded',
      services: {
        'openmeteo': ExternalServiceStatus.unknown(),
        'gibs': ExternalServiceStatus.unknown(),
        'noaa': ExternalServiceStatus.unknown(),
        'copernicus': ExternalServiceStatus.unknown(),
      },
      timestamp: DateTime.now().toIso8601String(),
    );
  }

  /// Create a healthy status (for testing)
  factory ServiceHealth.healthy() {
    final now = DateTime.now().toIso8601String();
    return ServiceHealth(
      status: 'healthy',
      services: {
        'openmeteo': ExternalServiceStatus(status: 'ok', lastChecked: now),
        'gibs': ExternalServiceStatus(status: 'ok', lastChecked: now),
        'noaa': ExternalServiceStatus(status: 'ok', lastChecked: now),
        'copernicus': ExternalServiceStatus(status: 'ok', lastChecked: now),
      },
      timestamp: now,
    );
  }
}
