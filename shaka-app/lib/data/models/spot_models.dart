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

  const SpotConditions({
    required this.visibility,
    required this.waterTemp,
    required this.swell,
    required this.wind,
    this.tideState = '',
  });

  factory SpotConditions.fromJson(Map<String, dynamic> json) {
    return SpotConditions(
      visibility: json['visibility'] ?? '',
      waterTemp: json['waterTemp'] ?? '',
      swell: json['swell'] ?? '',
      wind: json['wind'] ?? '',
      tideState: json['tideState'] ?? '',
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
  final String directions;
  final String parkingInfo;
  final bool permitRequired;

  const AccessInfo({
    required this.directions,
    required this.parkingInfo,
    this.permitRequired = false,
  });

  factory AccessInfo.fromJson(Map<String, dynamic> json) {
    return AccessInfo(
      directions: json['directions'] ?? '',
      parkingInfo: json['parkingInfo'] ?? '',
      permitRequired: json['permitRequired'] ?? false,
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

/// Satellite imagery data.
///
/// IMPORTANT: The color fields are for DISPLAY ONLY - they show what the satellite
/// captured but may include sediment, kelp, or bottom reflectance in coastal areas.
///
/// For actual chlorophyll measurements, use noaaErddapChlorophyll which comes from
/// NOAA CoastWatch ERDDAP - a reliable numerical data source.
class GibsSatelliteReadings {
  // Satellite imagery colors (display only - may include sediment/kelp contamination)
  final String? paceTodayColor;      // RGB hex "#RRGGBB" from PACE satellite
  final String? paceYesterdayColor;
  final String? noaa20TodayColor;    // RGB hex from NOAA-20 VIIRS
  final String? noaa20YesterdayColor;
  final String? noaa21TodayColor;    // RGB hex from NOAA-21 VIIRS
  final String? noaa21YesterdayColor;
  final String? sentinel3aTodayColor;  // RGB hex from Sentinel-3A OLCI
  final String? sentinel3aYesterdayColor;
  final String? sentinel3bTodayColor;  // RGB hex from Sentinel-3B OLCI
  final String? sentinel3bYesterdayColor;
  // Observation timestamps (when the satellite passed over)
  final DateTime? paceObservationTime;
  final DateTime? noaa20ObservationTime;
  final DateTime? noaa21ObservationTime;
  final String? dataDate; // The date "today" refers to
  // ACTUAL MEASURED CHLOROPHYLL from NOAA ERDDAP (the trusted source)
  final double? noaaErddapChlorophyll;  // mg/m³ - THE reliable chlorophyll value
  final DateTime? noaaErddapFetchTime;

  const GibsSatelliteReadings({
    this.paceTodayColor,
    this.paceYesterdayColor,
    this.noaa20TodayColor,
    this.noaa20YesterdayColor,
    this.noaa21TodayColor,
    this.noaa21YesterdayColor,
    this.sentinel3aTodayColor,
    this.sentinel3aYesterdayColor,
    this.sentinel3bTodayColor,
    this.sentinel3bYesterdayColor,
    this.paceObservationTime,
    this.noaa20ObservationTime,
    this.noaa21ObservationTime,
    this.dataDate,
    this.noaaErddapChlorophyll,
    this.noaaErddapFetchTime,
  });

  factory GibsSatelliteReadings.fromJson(Map<String, dynamic> json) {
    return GibsSatelliteReadings(
      paceTodayColor: json['paceTodayColor'] as String?,
      paceYesterdayColor: json['paceYesterdayColor'] as String?,
      noaa20TodayColor: json['noaa20TodayColor'] as String?,
      noaa20YesterdayColor: json['noaa20YesterdayColor'] as String?,
      noaa21TodayColor: json['noaa21TodayColor'] as String?,
      noaa21YesterdayColor: json['noaa21YesterdayColor'] as String?,
      sentinel3aTodayColor: json['sentinel3aTodayColor'] as String?,
      sentinel3aYesterdayColor: json['sentinel3aYesterdayColor'] as String?,
      sentinel3bTodayColor: json['sentinel3bTodayColor'] as String?,
      sentinel3bYesterdayColor: json['sentinel3bYesterdayColor'] as String?,
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

  /// Check if we have any data at all (colors or NOAA ERDDAP measurement)
  bool get hasAnyData =>
      paceTodayColor != null ||
      paceYesterdayColor != null ||
      noaa20TodayColor != null ||
      noaa20YesterdayColor != null ||
      noaa21TodayColor != null ||
      noaa21YesterdayColor != null ||
      sentinel3aTodayColor != null ||
      sentinel3aYesterdayColor != null ||
      sentinel3bTodayColor != null ||
      sentinel3bYesterdayColor != null ||
      noaaErddapChlorophyll != null;
}

/// Marine Protected Area status from ProtectedSeas Navigator
class MPAStatus {
  final bool isProtected;
  final bool isInsideMPA;  // True if spot is inside MPA boundary (not just nearby)
  final String? siteName;
  final String? designation;
  final int spearfishingStatus;  // 0=Allowed, 1=Prohibited, 2=Restricted, 3=Unknown
  final int protectionLevel;     // 1-5 Level of Fishing Protection
  final String? speciesOfConcern;
  final String? purpose;
  final String? detailsUrl;

  const MPAStatus({
    required this.isProtected,
    this.isInsideMPA = false,
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
      isInsideMPA: json['isInsideMPA'] ?? false,
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

// ===========================================
// FISHING INTEL MODELS
// Raw data for fishermen to interpret
// ===========================================

/// Vessel activity from Global Fishing Watch
class VesselActivity {
  final int count;
  final int radiusNm;
  final String updatedAt;

  const VesselActivity({
    required this.count,
    required this.radiusNm,
    required this.updatedAt,
  });

  factory VesselActivity.fromJson(Map<String, dynamic> json) {
    return VesselActivity(
      count: json['count'] ?? 0,
      radiusNm: json['radiusNm'] ?? 10,
      updatedAt: json['updatedAt'] ?? '',
    );
  }
}

/// Time period for solunar data
class TimePeriod {
  final String start;
  final String end;

  const TimePeriod({required this.start, required this.end});

  factory TimePeriod.fromJson(Map<String, dynamic> json) {
    return TimePeriod(
      start: json['start'] ?? '',
      end: json['end'] ?? '',
    );
  }
}

/// Solunar data - moon phase and feeding periods
class SolunarData {
  final String moonPhase;
  final int illumination;
  final List<TimePeriod> majorPeriods;
  final List<TimePeriod> minorPeriods;
  final int? dayRating;

  const SolunarData({
    required this.moonPhase,
    required this.illumination,
    required this.majorPeriods,
    required this.minorPeriods,
    this.dayRating,
  });

  factory SolunarData.fromJson(Map<String, dynamic> json) {
    return SolunarData(
      moonPhase: json['moonPhase'] ?? 'unknown',
      illumination: json['illumination'] ?? 0,
      majorPeriods: (json['majorPeriods'] as List? ?? [])
          .map((e) => TimePeriod.fromJson(e))
          .toList(),
      minorPeriods: (json['minorPeriods'] as List? ?? [])
          .map((e) => TimePeriod.fromJson(e))
          .toList(),
      dayRating: json['dayRating'],
    );
  }
  
  /// Get human-readable moon phase
  String get moonPhaseDisplay {
    return moonPhase.replaceAll('_', ' ').split(' ').map((word) => 
      word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : ''
    ).join(' ');
  }
}

/// Chlorophyll context with trend
class ChlorophyllContext {
  final double current;
  final double avg7day;
  final String trend;

  const ChlorophyllContext({
    required this.current,
    required this.avg7day,
    required this.trend,
  });

  factory ChlorophyllContext.fromJson(Map<String, dynamic> json) {
    return ChlorophyllContext(
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      avg7day: (json['avg7day'] as num?)?.toDouble() ?? 0.0,
      trend: json['trend'] ?? 'stable',
    );
  }
  
  /// Get ratio of current to average
  double get ratio => avg7day > 0 ? current / avg7day : 1.0;
}

/// SST reading at a nearby point
class SSTReading {
  final String direction;
  final int distanceNm;
  final double tempC;

  const SSTReading({
    required this.direction,
    required this.distanceNm,
    required this.tempC,
  });

  factory SSTReading.fromJson(Map<String, dynamic> json) {
    return SSTReading(
      direction: json['direction'] ?? '',
      distanceNm: json['distanceNm'] ?? 5,
      tempC: (json['tempC'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Enhanced water context
class WaterContext {
  final ChlorophyllContext? chlorophyll;
  final List<SSTReading>? sstNearby;

  const WaterContext({this.chlorophyll, this.sstNearby});

  factory WaterContext.fromJson(Map<String, dynamic> json) {
    return WaterContext(
      chlorophyll: json['chlorophyll'] != null
          ? ChlorophyllContext.fromJson(json['chlorophyll'])
          : null,
      sstNearby: (json['sstNearby'] as List?)
          ?.map((e) => SSTReading.fromJson(e))
          .toList(),
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
  // NEW: Fishing intel data
  final VesselActivity? vessels;
  final SolunarData? solunar;
  final WaterContext? waterContext;

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
    this.vessels,
    this.solunar,
    this.waterContext,
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
      vessels: json['vessels'] != null
          ? VesselActivity.fromJson(json['vessels'])
          : null,
      solunar: json['solunar'] != null
          ? SolunarData.fromJson(json['solunar'])
          : null,
      waterContext: json['waterContext'] != null
          ? WaterContext.fromJson(json['waterContext'])
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
  final int shakaScore;

  const SpotSearchResult({
    required this.id,
    required this.name,
    required this.region,
    required this.coordinates,
    this.shakaScore = 0,
  });

  factory SpotSearchResult.fromJson(Map<String, dynamic> json) {
    return SpotSearchResult(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      region: json['region'] ?? '',
      coordinates: Coordinates.fromJson(json['coordinates'] ?? {}),
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

// ===========================================
// USER SPOTS MODELS
// ===========================================

/// Response from creating/fetching a user spot
class UserSpotResponse {
  final String id;
  final String name;
  final Coordinates coordinates;  // Uses existing Coordinates class
  final String region;
  final String country;
  final DateTime createdAt;
  final bool isUserSpot;
  final int? shakaScore;  // Latest Shaka Score (if available from API)

  UserSpotResponse({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.region,
    required this.country,
    required this.createdAt,
    this.isUserSpot = true,
    this.shakaScore,
  });

  // Convenience getters
  double get latitude => coordinates.lat;
  double get longitude => coordinates.lon;

  factory UserSpotResponse.fromJson(Map<String, dynamic> json) {
    return UserSpotResponse(
      id: json['id'] as String,
      name: json['name'] as String,
      coordinates: Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>),
      region: json['region'] as String,
      country: json['country'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isUserSpot: json['isUserSpot'] as bool? ?? true,
      shakaScore: json['shakaScore'] as int?,
    );
  }
}

/// Response containing list of user spots
class UserSpotsListResponse {
  final List<UserSpotResponse> spots;
  final int count;
  final int limit;

  UserSpotsListResponse({
    required this.spots,
    required this.count,
    this.limit = 100,
  });

  factory UserSpotsListResponse.fromJson(Map<String, dynamic> json) {
    final spotsList = (json['spots'] as List)
        .map((s) => UserSpotResponse.fromJson(s as Map<String, dynamic>))
        .toList();
    return UserSpotsListResponse(
      spots: spotsList,
      count: json['count'] as int,
      limit: json['limit'] as int? ?? 100,
    );
  }
}

/// Response from getUserSpotDetail endpoint
class UserSpotDetailResponse {
  final SpotDetail spot;
  final bool isUserSpot;

  UserSpotDetailResponse({
    required this.spot,
    this.isUserSpot = true,
  });

  factory UserSpotDetailResponse.fromJson(Map<String, dynamic> json) {
    return UserSpotDetailResponse(
      spot: SpotDetail.fromJson(json['spot'] as Map<String, dynamic>),
      isUserSpot: json['isUserSpot'] as bool? ?? true,
    );
  }
}
