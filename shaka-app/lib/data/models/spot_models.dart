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
  final String? swellCorrected;
  final String? secondarySwell;
  final String? secondarySwellCorrected;
  final int? exposureBearing;
  final int? exposureWidth;
  final double? bathymetryDepthM;
  // Raw numeric fields for client-side unit conversion
  final double? swellHeightFt;
  final double? swellPeriodSec;
  final String? swellDirection;
  final double? windSpeedKts;
  final String? windDirectionCardinal;
  final double? waterTempC;
  // Actual retrieval timestamps (epoch millis) for the Data Sources flyout.
  final int? swellRetrievedAt;
  final int? windRetrievedAt;

  const SpotConditions({
    required this.visibility,
    required this.waterTemp,
    required this.swell,
    required this.wind,
    this.tideState = '',
    this.swellCorrected,
    this.secondarySwell,
    this.secondarySwellCorrected,
    this.exposureBearing,
    this.exposureWidth,
    this.bathymetryDepthM,
    this.swellHeightFt,
    this.swellPeriodSec,
    this.swellDirection,
    this.windSpeedKts,
    this.windDirectionCardinal,
    this.waterTempC,
    this.swellRetrievedAt,
    this.windRetrievedAt,
  });

  factory SpotConditions.fromJson(Map<String, dynamic> json) {
    return SpotConditions(
      visibility: json['visibility'] ?? '',
      waterTemp: json['waterTemp'] ?? '',
      swell: json['swell'] ?? '',
      wind: json['wind'] ?? '',
      tideState: json['tideState'] ?? '',
      swellCorrected: json['swellCorrected'],
      secondarySwell: json['secondarySwell'],
      secondarySwellCorrected: json['secondarySwellCorrected'],
      exposureBearing: json['exposureBearing'],
      exposureWidth: json['exposureWidth'],
      bathymetryDepthM: (json['bathymetryDepthM'] as num?)?.toDouble(),
      swellHeightFt: (json['swellHeightFt'] as num?)?.toDouble(),
      swellPeriodSec: (json['swellPeriodSec'] as num?)?.toDouble(),
      swellDirection: json['swellDirection'],
      windSpeedKts: (json['windSpeedKts'] as num?)?.toDouble(),
      windDirectionCardinal: json['windDirectionCardinal'],
      waterTempC: (json['waterTempC'] as num?)?.toDouble(),
      swellRetrievedAt: (json['swellRetrievedAt'] as num?)?.toInt(),
      windRetrievedAt: (json['windRetrievedAt'] as num?)?.toInt(),
    );
  }
}

/// Near-real-time wind fetched by the detail screen AFTER first paint
/// (GET /spots/{id}/wind/live), so the detail load itself stays instant.
class LiveWind {
  final double windSpeedKts;
  final String? windDirectionCardinal;
  final double? gustKts;
  final int retrievedAt;

  const LiveWind({
    required this.windSpeedKts,
    this.windDirectionCardinal,
    this.gustKts,
    required this.retrievedAt,
  });

  factory LiveWind.fromJson(Map<String, dynamic> json) {
    return LiveWind(
      windSpeedKts: (json['windSpeedKts'] as num).toDouble(),
      windDirectionCardinal: json['windDirectionCardinal'] as String?,
      gustKts: (json['gustKts'] as num?)?.toDouble(),
      retrievedAt: (json['retrievedAt'] as num).toInt(),
    );
  }
}

class ScoreBreakdown {
  final int visibility;
  final int weather;
  final int swell;
  final int solunar;

  const ScoreBreakdown({
    required this.visibility,
    required this.weather,
    required this.swell,
    required this.solunar,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) {
    return ScoreBreakdown(
      visibility: json['visibility'] ?? 0,
      weather: json['weather'] ?? 0,
      swell: json['swell'] ?? 0,
      solunar: json['solunar'] ?? 0,
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
/// For actual chlorophyll measurements, use chlorophyllMgM3 (Copernicus Marine).
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
  // Measured chlorophyll-a (mg/m³) from Copernicus Marine (the old
  // "noaaErddapChlorophyll" API name was misleading; parsing falls back to it
  // for older API responses).
  final double? chlorophyllMgM3;
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
    this.chlorophyllMgM3,
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
      chlorophyllMgM3: ((json['chlorophyllMgM3'] ?? json['noaaErddapChlorophyll']) as num?)
          ?.toDouble(),
      noaaErddapFetchTime: json['noaaErddapFetchTime'] != null
          ? DateTime.tryParse(json['noaaErddapFetchTime'])
          : null,
    );
  }

  /// Check if we have any data at all (colors or measured chlorophyll)
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
      chlorophyllMgM3 != null;
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

  /// Locale-level license requirement: "required" | "conditional" |
  /// "not_required" | "prohibited". Null when unknown (or old server).
  final String? licenseRequirement;
  final String? note;
  final MPAStatus? mpaStatus;
  final bool mpaChecked; // true when MPA fetch was attempted (mpa_fetched_at is NOT NULL)

  const RegulationInfo({
    required this.regulatoryAgency,
    required this.regulationsUrl,
    this.licensingUrl,
    this.licenseRequirement,
    this.note,
    this.mpaStatus,
    this.mpaChecked = false,
  });

  factory RegulationInfo.fromJson(Map<String, dynamic> json) {
    return RegulationInfo(
      regulatoryAgency: json['regulatoryAgency'] ?? 'Fisheries Authority',
      regulationsUrl: json['regulationsUrl'] ?? 'https://navigatormap.org/',
      licensingUrl: json['licensingUrl'],
      licenseRequirement: json['licenseRequirement'] as String?,
      note: json['note'],
      mpaStatus: json['mpaStatus'] != null
          ? MPAStatus.fromJson(json['mpaStatus'])
          : null,
      mpaChecked: json['mpaChecked'] as bool? ?? false,
    );
  }
}

// ===========================================
// FISHING INTEL MODELS
// Raw data for fishermen to interpret
// ===========================================

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

class TidePoint {
  final int epochMs;
  final double heightFt;

  const TidePoint({required this.epochMs, required this.heightFt});

  factory TidePoint.fromJson(Map<String, dynamic> json) {
    return TidePoint(
      epochMs: json['epochMs'] ?? 0,
      heightFt: (json['heightFt'] as num?)?.toDouble() ?? 0.0,
    );
  }

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epochMs);
}

class TideExtreme {
  final int epochMs;
  final double heightFt;
  final String type; // "H" or "L"

  const TideExtreme({
    required this.epochMs,
    required this.heightFt,
    required this.type,
  });

  factory TideExtreme.fromJson(Map<String, dynamic> json) {
    return TideExtreme(
      epochMs: json['epochMs'] ?? 0,
      heightFt: (json['heightFt'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] ?? 'H',
    );
  }

  bool get isHigh => type == 'H';
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epochMs);
}

class TideChartData {
  final String provider;
  final String stationId;
  final String stationName;
  final double stationDistanceMi;
  final String datum;
  final String timezoneId;
  final List<TidePoint> points;
  final List<TideExtreme> extremes;
  final double? currentHeightFt;
  final String? currentStage;
  final bool available;
  final String localDate;

  const TideChartData({
    required this.provider,
    required this.stationId,
    required this.stationName,
    required this.stationDistanceMi,
    required this.datum,
    required this.timezoneId,
    required this.points,
    required this.extremes,
    this.currentHeightFt,
    this.currentStage,
    this.available = true,
    this.localDate = '',
  });

  factory TideChartData.fromJson(Map<String, dynamic> json) {
    final rawExtremes = (json['extremes'] as List? ?? [])
        .map((e) => TideExtreme.fromJson(e))
        .toList();
    return TideChartData(
      provider: json['provider'] ?? 'noaa',
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      stationDistanceMi: (json['stationDistanceMi'] as num?)?.toDouble() ?? 0.0,
      datum: json['datum'] ?? 'MLLW',
      timezoneId: json['timezoneId'] ?? '',
      points: (json['points'] as List? ?? [])
          .map((e) => TidePoint.fromJson(e))
          .toList(),
      extremes: _mergeExtremes(rawExtremes),
      currentHeightFt: (json['currentHeightFt'] as num?)?.toDouble(),
      currentStage: json['currentStage'],
      available: json['available'] ?? true,
      localDate: json['localDate'] ?? '',
    );
  }

  static const _mergeWindowMs = 3 * 3600000; // 3 hours

  static List<TideExtreme> _mergeExtremes(List<TideExtreme> raw) {
    if (raw.length <= 1) return raw;
    final sorted = List<TideExtreme>.from(raw)
      ..sort((a, b) => a.epochMs.compareTo(b.epochMs));

    final merged = <TideExtreme>[];
    var cluster = <TideExtreme>[sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].epochMs - cluster.first.epochMs <= _mergeWindowMs) {
        cluster.add(sorted[i]);
      } else {
        merged.add(_pickRepresentative(cluster));
        cluster = [sorted[i]];
      }
    }
    merged.add(_pickRepresentative(cluster));

    final reclassified = _reclassifyTypes(merged);

    double totalRange = 0;
    if (raw.isNotEmpty) {
      final maxH = raw.map((e) => e.heightFt).reduce((a, b) => a > b ? a : b);
      final minH = raw.map((e) => e.heightFt).reduce((a, b) => a < b ? a : b);
      totalRange = maxH - minH;
    }
    return _filterByProminence(reclassified, totalRange);
  }

  static TideExtreme _pickRepresentative(List<TideExtreme> cluster) {
    final maxPt = cluster.reduce(
        (a, b) => a.heightFt >= b.heightFt ? a : b);
    final minPt = cluster.reduce(
        (a, b) => a.heightFt <= b.heightFt ? a : b);
    final meanH = cluster.fold(0.0, (s, e) => s + e.heightFt) / cluster.length;
    final best = (maxPt.heightFt - meanH).abs() >= (minPt.heightFt - meanH).abs()
        ? maxPt
        : minPt;
    return TideExtreme(epochMs: best.epochMs, heightFt: best.heightFt, type: best.type);
  }

  static List<TideExtreme> _reclassifyTypes(List<TideExtreme> merged) {
    final n = merged.length;
    if (n <= 1) return merged;
    final result = <TideExtreme>[];
    for (int i = 0; i < n; i++) {
      final higherThanPrev =
          i == 0 || merged[i].heightFt > merged[i - 1].heightFt;
      final higherThanNext =
          i == n - 1 || merged[i].heightFt > merged[i + 1].heightFt;
      final type = (higherThanPrev && higherThanNext) ? 'H' : 'L';
      result.add(TideExtreme(
          epochMs: merged[i].epochMs,
          heightFt: merged[i].heightFt,
          type: type));
    }
    return result;
  }

  static List<TideExtreme> _filterByProminence(
      List<TideExtreme> merged, double totalRange) {
    if (merged.length <= 2) return merged;
    final threshold = totalRange * 0.05 < 0.1 ? 0.1 : totalRange * 0.05;
    final result = <TideExtreme>[];
    for (int i = 0; i < merged.length; i++) {
      if (i == 0 || i == merged.length - 1) {
        result.add(merged[i]);
        continue;
      }
      final diffPrev = (merged[i].heightFt - merged[i - 1].heightFt).abs();
      final diffNext = (merged[i].heightFt - merged[i + 1].heightFt).abs();
      if (diffPrev < diffNext ? diffPrev >= threshold : diffNext >= threshold) {
        result.add(merged[i]);
      }
    }
    return result.length != merged.length ? _reclassifyTypes(result) : result;
  }

  TideExtreme? get nextHigh {
    final now = DateTime.now().millisecondsSinceEpoch;
    final future = extremes.where((e) => e.isHigh && e.epochMs > now);
    return future.isEmpty ? null : future.first;
  }

  TideExtreme? get nextLow {
    final now = DateTime.now().millisecondsSinceEpoch;
    final future = extremes.where((e) => !e.isHigh && e.epochMs > now);
    return future.isEmpty ? null : future.first;
  }

  List<TideExtreme> get highs {
    final all = extremes.where((e) => e.isHigh).toList()
      ..sort((a, b) => a.epochMs.compareTo(b.epochMs));
    return all.length > 2 ? all.sublist(0, 2) : all;
  }

  List<TideExtreme> get lows {
    final all = extremes.where((e) => !e.isHigh).toList()
      ..sort((a, b) => a.epochMs.compareTo(b.epochMs));
    return all.length > 2 ? all.sublist(0, 2) : all;
  }
}

/// One hourly swell sample. epochMs is absolute so "now" selection stays
/// timezone-agnostic, mirroring [TidePoint].
class SwellHourlyPoint {
  final int epochMs;
  final double heightFt;
  final double periodSec;
  final int directionDeg;
  final double? correctedHeightFt;
  final double? secondaryHeightFt;
  final double? secondaryPeriodSec;
  final int? secondaryDirectionDeg;
  final double? secondaryCorrectedHeightFt;

  const SwellHourlyPoint({
    required this.epochMs,
    required this.heightFt,
    required this.periodSec,
    required this.directionDeg,
    this.correctedHeightFt,
    this.secondaryHeightFt,
    this.secondaryPeriodSec,
    this.secondaryDirectionDeg,
    this.secondaryCorrectedHeightFt,
  });

  /// Exposure-corrected height when available, else the raw height.
  double get effectiveHeightFt => correctedHeightFt ?? heightFt;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epochMs);

  factory SwellHourlyPoint.fromJson(Map<String, dynamic> json) {
    return SwellHourlyPoint(
      epochMs: json['epochMs'] ?? 0,
      heightFt: (json['heightFt'] as num?)?.toDouble() ?? 0.0,
      periodSec: (json['periodSec'] as num?)?.toDouble() ?? 0.0,
      directionDeg: (json['directionDeg'] as num?)?.toInt() ?? 0,
      correctedHeightFt: (json['correctedHeightFt'] as num?)?.toDouble(),
      secondaryHeightFt: (json['secondaryHeightFt'] as num?)?.toDouble(),
      secondaryPeriodSec: (json['secondaryPeriodSec'] as num?)?.toDouble(),
      secondaryDirectionDeg: (json['secondaryDirectionDeg'] as num?)?.toInt(),
      secondaryCorrectedHeightFt:
          (json['secondaryCorrectedHeightFt'] as num?)?.toDouble(),
    );
  }
}

/// One hourly wind sample. epochMs is absolute, mirroring [SwellHourlyPoint].
class WindHourlyPoint {
  final int epochMs;
  final double speedKts;
  final int directionDeg;
  final double? gustKts;

  const WindHourlyPoint({
    required this.epochMs,
    required this.speedKts,
    required this.directionDeg,
    this.gustKts,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epochMs);

  factory WindHourlyPoint.fromJson(Map<String, dynamic> json) {
    return WindHourlyPoint(
      epochMs: json['epochMs'] ?? 0,
      speedKts: (json['speedKts'] as num?)?.toDouble() ?? 0.0,
      directionDeg: (json['directionDeg'] as num?)?.toInt() ?? 0,
      gustKts: (json['gustKts'] as num?)?.toDouble(),
    );
  }
}

/// One spot-local day of hourly swell + wind points. The backend groups by the
/// spot's timezone so the client never computes date boundaries.
class SpotHourlyDay {
  final String localDate;
  final List<SwellHourlyPoint> swell;
  final List<WindHourlyPoint> wind;

  const SpotHourlyDay({
    required this.localDate,
    required this.swell,
    required this.wind,
  });

  factory SpotHourlyDay.fromJson(Map<String, dynamic> json) {
    return SpotHourlyDay(
      localDate: json['localDate'] ?? '',
      swell: (json['swell'] as List? ?? [])
          .map((e) => SwellHourlyPoint.fromJson(e))
          .toList(),
      wind: (json['wind'] as List? ?? [])
          .map((e) => WindHourlyPoint.fromJson(e))
          .toList(),
    );
  }
}

/// Hourly swell + wind curves grouped by spot-local day. days[0] is "today".
class SpotHourlyResponse {
  final String spotId;
  final String? timezoneId;
  final List<SpotHourlyDay> days;

  const SpotHourlyResponse({
    required this.spotId,
    required this.timezoneId,
    required this.days,
  });

  factory SpotHourlyResponse.fromJson(Map<String, dynamic> json) {
    return SpotHourlyResponse(
      spotId: json['spotId'] ?? '',
      timezoneId: json['timezoneId'],
      days: (json['days'] as List? ?? [])
          .map((e) => SpotHourlyDay.fromJson(e))
          .toList(),
    );
  }
}

/// Multi-day tide chart curves, one [TideChartData] per spot-local day starting
/// at today. Only days[0] carries currentHeightFt / currentStage.
class SpotTideRangeResponse {
  final String spotId;
  final String? timezoneId;
  final List<TideChartData> days;

  const SpotTideRangeResponse({
    required this.spotId,
    required this.timezoneId,
    required this.days,
  });

  factory SpotTideRangeResponse.fromJson(Map<String, dynamic> json) {
    return SpotTideRangeResponse(
      spotId: json['spotId'] ?? '',
      timezoneId: json['timezoneId'],
      days: (json['days'] as List? ?? [])
          .map((e) => TideChartData.fromJson(e))
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
  final List<GearItem> gearRecommendations;
  final List<RiskInfo> risks;
  final List<CommunityReport> communityReports;
  final String bestTimeOfDay;
  final String? imageUrl;
  final GibsSatelliteReadings? satelliteReadings;
  final RegulationInfo? regulations;
  final SolunarData? solunar;
  final WaterContext? waterContext;
  final TideChartData? tide;

  const SpotDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.coordinates,
    required this.score,
    required this.access,
    required this.conditions,
    required this.forecast,
    required this.gearRecommendations,
    required this.risks,
    required this.communityReports,
    required this.bestTimeOfDay,
    this.imageUrl,
    this.satelliteReadings,
    this.regulations,
    this.solunar,
    this.waterContext,
    this.tide,
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
      solunar: json['solunar'] != null
          ? SolunarData.fromJson(json['solunar'])
          : null,
      waterContext: json['waterContext'] != null
          ? WaterContext.fromJson(json['waterContext'])
          : null,
      tide: json['tide'] != null
          ? TideChartData.fromJson(json['tide'])
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
  final Coordinates coordinates;
  final String region;
  final String country;
  final DateTime createdAt;
  final bool isUserSpot;
  final int? shakaScore;
  final String? visibility;
  final String? swell;
  final String? wind;
  final String? waterTemp;
  final double? waterTempC;
  final double? swellHeightFt;
  final double? windSpeedKts;

  UserSpotResponse({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.region,
    required this.country,
    required this.createdAt,
    this.isUserSpot = true,
    this.shakaScore,
    this.visibility,
    this.swell,
    this.wind,
    this.waterTemp,
    this.waterTempC,
    this.swellHeightFt,
    this.windSpeedKts,
  });

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
      visibility: json['visibility'] as String?,
      swell: json['swell'] as String?,
      wind: json['wind'] as String?,
      waterTemp: json['waterTemp'] as String?,
      waterTempC: (json['waterTempC'] as num?)?.toDouble(),
      swellHeightFt: (json['swellHeightFt'] as num?)?.toDouble(),
      windSpeedKts: (json['windSpeedKts'] as num?)?.toDouble(),
    );
  }

  SpotMapMarker toSpotMapMarker() {
    return SpotMapMarker(
      id: id,
      name: name,
      coordinates: coordinates,
      region: region,
      shakaScore: shakaScore,
      visibility: visibility,
      swell: swell,
      wind: wind,
      waterTemp: waterTemp,
      isUserSpot: true,
      waterTempC: waterTempC,
      swellHeightFt: swellHeightFt,
      windSpeedKts: windSpeedKts,
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

// ===========================================
// ALL SPOTS (MAP MARKERS) MODELS
// Lightweight data for displaying all spots on map
// ===========================================

/// Lightweight spot data for map markers.
/// Contains score and basic conditions from cache for carousel display.
class SpotMapMarker {
  final String id;
  final String name;
  final Coordinates coordinates;
  final String region;
  final int? shakaScore;
  final String? visibility;
  final String? swell;
  final String? wind;
  final String? waterTemp;
  final bool isUserSpot;
  // Raw numeric fields for client-side unit conversion
  final double? waterTempC;
  final double? swellHeightFt;
  final double? windSpeedKts;

  const SpotMapMarker({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.region,
    this.shakaScore,
    this.visibility,
    this.swell,
    this.wind,
    this.waterTemp,
    this.isUserSpot = false,
    this.waterTempC,
    this.swellHeightFt,
    this.windSpeedKts,
  });

  factory SpotMapMarker.fromJson(Map<String, dynamic> json) {
    return SpotMapMarker(
      id: json['id'] as String,
      name: json['name'] as String,
      coordinates: Coordinates.fromJson(json['coordinates'] as Map<String, dynamic>),
      region: json['region'] as String,
      shakaScore: json['shakaScore'] as int?,
      visibility: json['visibility'] as String?,
      swell: json['swell'] as String?,
      wind: json['wind'] as String?,
      waterTemp: json['waterTemp'] as String?,
      waterTempC: (json['waterTempC'] as num?)?.toDouble(),
      swellHeightFt: (json['swellHeightFt'] as num?)?.toDouble(),
      windSpeedKts: (json['windSpeedKts'] as num?)?.toDouble(),
    );
  }
}

/// Response from /spots/all endpoint
class AllSpotsResponse {
  final List<SpotMapMarker> spots;
  final int count;

  const AllSpotsResponse({
    required this.spots,
    required this.count,
  });

  factory AllSpotsResponse.fromJson(Map<String, dynamic> json) {
    return AllSpotsResponse(
      spots: (json['spots'] as List)
          .map((s) => SpotMapMarker.fromJson(s as Map<String, dynamic>))
          .toList(),
      count: json['count'] as int,
    );
  }
}
