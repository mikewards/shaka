/// Fishing intel response - focused on what's HOT!
class FishingIntelResponse {
  final String spotId;
  final Headline? headline;
  final List<TrendingSpecies> hotSpecies;
  final List<TrendingSpecies> coldSpecies;
  final List<RecentCatch> recentCatches;
  final List<String> sourcesUsed;
  final String dataFreshness;
  final int totalReports;

  const FishingIntelResponse({
    required this.spotId,
    this.headline,
    required this.hotSpecies,
    required this.coldSpecies,
    required this.recentCatches,
    required this.sourcesUsed,
    required this.dataFreshness,
    required this.totalReports,
  });

  factory FishingIntelResponse.fromJson(Map<String, dynamic> json) {
    return FishingIntelResponse(
      spotId: json['spotId'] ?? '',
      headline: json['headline'] != null 
          ? Headline.fromJson(json['headline']) 
          : null,
      hotSpecies: (json['hotSpecies'] as List? ?? [])
          .map((e) => TrendingSpecies.fromJson(e))
          .toList(),
      coldSpecies: (json['coldSpecies'] as List? ?? [])
          .map((e) => TrendingSpecies.fromJson(e))
          .toList(),
      recentCatches: (json['recentCatches'] as List? ?? [])
          .map((e) => RecentCatch.fromJson(e))
          .toList(),
      sourcesUsed: (json['sourcesUsed'] as List? ?? []).cast<String>(),
      dataFreshness: json['dataFreshness'] ?? '',
      totalReports: json['totalReports'] ?? 0,
    );
  }
  
  bool get hasData => headline != null || hotSpecies.isNotEmpty || recentCatches.isNotEmpty;
}

/// The headline - what's the #1 story?
class Headline {
  final String species;
  final String message;
  final int heatLevel; // 1-3 (warm, hot, on fire)
  final int count24h;
  final String? topLanding;

  const Headline({
    required this.species,
    required this.message,
    required this.heatLevel,
    required this.count24h,
    this.topLanding,
  });

  factory Headline.fromJson(Map<String, dynamic> json) {
    return Headline(
      species: json['species'] ?? '',
      message: json['message'] ?? '',
      heatLevel: json['heatLevel'] ?? 1,
      count24h: json['count24h'] ?? 0,
      topLanding: json['topLanding'],
    );
  }
}

/// Species with trend info
class TrendingSpecies {
  final String species;
  final int count24h;
  final int countPrevious;
  final String trend; // "UP", "DOWN", "STABLE"
  final int percentChange;
  final String? topLanding;

  const TrendingSpecies({
    required this.species,
    required this.count24h,
    required this.countPrevious,
    required this.trend,
    required this.percentChange,
    this.topLanding,
  });

  factory TrendingSpecies.fromJson(Map<String, dynamic> json) {
    return TrendingSpecies(
      species: json['species'] ?? '',
      count24h: json['count24h'] ?? 0,
      countPrevious: json['countPrevious'] ?? 0,
      trend: json['trend'] ?? 'STABLE',
      percentChange: json['percentChange'] ?? 0,
      topLanding: json['topLanding'],
    );
  }
  
  bool get isUp => trend == 'UP';
  bool get isDown => trend == 'DOWN';
}

/// Recent catch report
class RecentCatch {
  final String species;
  final int count;
  final String? boatName;
  final String landingName;
  final int hoursAgo;
  final String sourceName;

  const RecentCatch({
    required this.species,
    required this.count,
    this.boatName,
    required this.landingName,
    required this.hoursAgo,
    required this.sourceName,
  });

  factory RecentCatch.fromJson(Map<String, dynamic> json) {
    return RecentCatch(
      species: json['species'] ?? '',
      count: json['count'] ?? 0,
      boatName: json['boatName'],
      landingName: json['landingName'] ?? '',
      hoursAgo: json['hoursAgo'] ?? 0,
      sourceName: json['sourceName'] ?? '',
    );
  }
  
  String get timeDisplay {
    if (hoursAgo == 0) return 'Just now';
    if (hoursAgo == 1) return '1 hour ago';
    if (hoursAgo < 24) return '$hoursAgo hours ago';
    final days = hoursAgo ~/ 24;
    return days == 1 ? 'Yesterday' : '$days days ago';
  }
}

// Legacy types for backwards compatibility
class IntelHighlight {
  final String type;
  final String species;
  final int? countKept;
  final int? countReleased;
  final String? boatName;
  final String landingName;
  final double distanceMi;
  final String publishedAt;
  final String excerpt;
  final String sourceUrl;
  final String sourceName;
  final List<String> corroboratedBy;

  const IntelHighlight({
    required this.type,
    required this.species,
    this.countKept,
    this.countReleased,
    this.boatName,
    required this.landingName,
    required this.distanceMi,
    required this.publishedAt,
    required this.excerpt,
    required this.sourceUrl,
    required this.sourceName,
    required this.corroboratedBy,
  });

  factory IntelHighlight.fromJson(Map<String, dynamic> json) {
    return IntelHighlight(
      type: json['type'] ?? '',
      species: json['species'] ?? '',
      countKept: json['countKept'],
      countReleased: json['countReleased'],
      boatName: json['boatName'],
      landingName: json['landingName'] ?? '',
      distanceMi: (json['distanceMi'] as num?)?.toDouble() ?? 0,
      publishedAt: json['publishedAt'] ?? '',
      excerpt: json['excerpt'] ?? '',
      sourceUrl: json['sourceUrl'] ?? '',
      sourceName: json['sourceName'] ?? '',
      corroboratedBy: (json['corroboratedBy'] as List? ?? []).cast<String>(),
    );
  }
}

class SpeciesSummary {
  final String species;
  final int totalKept;
  final int totalReleased;
  final int reportCount;

  const SpeciesSummary({
    required this.species,
    required this.totalKept,
    required this.totalReleased,
    required this.reportCount,
  });

  factory SpeciesSummary.fromJson(Map<String, dynamic> json) {
    return SpeciesSummary(
      species: json['species'] ?? '',
      totalKept: json['totalKept'] ?? 0,
      totalReleased: json['totalReleased'] ?? 0,
      reportCount: json['reportCount'] ?? 0,
    );
  }
}

class BaitStatus {
  final String location;
  final String baitType;
  final String status;
  final String updatedAt;

  const BaitStatus({
    required this.location,
    required this.baitType,
    required this.status,
    required this.updatedAt,
  });

  factory BaitStatus.fromJson(Map<String, dynamic> json) {
    return BaitStatus(
      location: json['location'] ?? '',
      baitType: json['baitType'] ?? '',
      status: json['status'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }
}
