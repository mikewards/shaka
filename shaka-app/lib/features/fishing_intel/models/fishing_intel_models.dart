/// Narrative insight: "where it's firing" from BD Outdoors etc.
class NarrativeInsight {
  final String species;
  final String location;
  final String excerpt;
  final String sourceName;
  final String threadUrl;
  final String publishedAt;
  final String tldr;
  final String? threadZone;

  const NarrativeInsight({
    required this.species,
    required this.location,
    required this.excerpt,
    required this.sourceName,
    required this.threadUrl,
    required this.publishedAt,
    this.tldr = '',
    this.threadZone,
  });

  factory NarrativeInsight.fromJson(Map<String, dynamic> json) {
    return NarrativeInsight(
      species: json['species'] ?? '',
      location: json['location'] ?? '',
      excerpt: json['excerpt'] ?? '',
      sourceName: json['sourceName'] ?? '',
      threadUrl: json['threadUrl'] ?? '',
      publishedAt: json['publishedAt'] ?? '',
      tldr: json['tldr'] ?? '',
      threadZone: json['threadZone'],
    );
  }
}

/// Fishing intel response - one list, desirability order, last 48h vs 5-day baseline (×2/5).
class FishingIntelResponse {
  final String spotId;
  final Headline? headline;
  final List<TrendingSpecies> hotSpecies;
  final List<TrendingSpecies> coldSpecies;
  /// Single list sorted by desirability (most to least). Prefer over hot/cold.
  final List<TrendingSpecies> speciesWithTrends;
  final List<RecentCatch> recentCatches;
  final List<String> sourcesUsed;
  final String dataFreshness;
  final int totalReports;
  final List<NarrativeInsight> narrativeInsights;
  /// Key insights for fishermen (Groq-generated, Hemingway-style, max 2 lines each).
  final List<String> keyInsights;

  const FishingIntelResponse({
    required this.spotId,
    this.headline,
    required this.hotSpecies,
    required this.coldSpecies,
    this.speciesWithTrends = const [],
    required this.recentCatches,
    required this.sourcesUsed,
    required this.dataFreshness,
    required this.totalReports,
    this.narrativeInsights = const [],
    this.keyInsights = const [],
  });

  factory FishingIntelResponse.fromJson(Map<String, dynamic> json) {
    final hot = (json['hotSpecies'] as List? ?? []).map((e) => TrendingSpecies.fromJson(e)).toList();
    final cold = (json['coldSpecies'] as List? ?? []).map((e) => TrendingSpecies.fromJson(e)).toList();
    final speciesWithTrends = (json['speciesWithTrends'] as List? ?? [])
        .map((e) => TrendingSpecies.fromJson(e))
        .toList();
    return FishingIntelResponse(
      spotId: json['spotId'] ?? '',
      headline: json['headline'] != null ? Headline.fromJson(json['headline']) : null,
      hotSpecies: hot,
      coldSpecies: cold,
      speciesWithTrends: speciesWithTrends.isNotEmpty ? speciesWithTrends : [...hot, ...cold],
      recentCatches: (json['recentCatches'] as List? ?? []).map((e) => RecentCatch.fromJson(e)).toList(),
      sourcesUsed: (json['sourcesUsed'] as List? ?? []).cast<String>(),
      dataFreshness: json['dataFreshness'] ?? '',
      totalReports: json['totalReports'] ?? 0,
      narrativeInsights: (json['narrativeInsights'] as List? ?? [])
          .map((e) => NarrativeInsight.fromJson(e as Map<String, dynamic>))
          .toList(),
      keyInsights: (json['keyInsights'] as List? ?? []).cast<String>(),
    );
  }

  /// Species list to show: backend list if present, else hot + cold for old API.
  List<TrendingSpecies> get speciesList =>
      speciesWithTrends.isNotEmpty ? speciesWithTrends : [...hotSpecies, ...coldSpecies];

  bool get hasData =>
      headline != null ||
      speciesList.isNotEmpty ||
      recentCatches.isNotEmpty ||
      narrativeInsights.isNotEmpty ||
      keyInsights.isNotEmpty;
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

/// Species with trend info (last 48h vs 5-day baseline ×2/5).
class TrendingSpecies {
  final String species;
  /// Catches in last 48h (field name count24h kept for API compat).
  final int count24h;
  final int countPrevious;
  final String trend; // "UP", "DOWN", "STABLE"
  final int percentChange;
  final String? topLanding;
  /// "Above average", "Below average", "Average", "New!"
  final String? trendLabel;

  const TrendingSpecies({
    required this.species,
    required this.count24h,
    required this.countPrevious,
    required this.trend,
    required this.percentChange,
    this.topLanding,
    this.trendLabel,
  });

  factory TrendingSpecies.fromJson(Map<String, dynamic> json) {
    return TrendingSpecies(
      species: json['species'] ?? '',
      count24h: json['count24h'] ?? 0,
      countPrevious: json['countPrevious'] ?? 0,
      trend: json['trend'] ?? 'STABLE',
      percentChange: json['percentChange'] ?? 0,
      topLanding: json['topLanding'],
      trendLabel: json['trendLabel'],
    );
  }

  String get primaryLabel {
    if (trendLabel != null && trendLabel!.isNotEmpty) return trendLabel!;
    if (percentChange > 500) return 'New!';
    if (trend == 'UP') return 'Above average';
    if (trend == 'DOWN') return 'Below average';
    return 'Average';
  }

  String get secondaryLabel {
    if (percentChange > 500) return '';
    final p = percentChange;
    final sign = p > 0 ? '+' : '';
    return '$sign$p% vs trailing 5-days';
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
