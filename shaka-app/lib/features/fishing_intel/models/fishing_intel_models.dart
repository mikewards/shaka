class FishingIntelResponse {
  final String spotId;
  final List<IntelHighlight> highlights;
  final List<SpeciesSummary> speciesSummary;
  final List<BaitStatus> baitStatus;
  final List<String> sourcesUsed;
  final String dataFreshness;

  const FishingIntelResponse({
    required this.spotId,
    required this.highlights,
    required this.speciesSummary,
    required this.baitStatus,
    required this.sourcesUsed,
    required this.dataFreshness,
  });

  factory FishingIntelResponse.fromJson(Map<String, dynamic> json) {
    return FishingIntelResponse(
      spotId: json['spotId'] ?? '',
      highlights: (json['highlights'] as List? ?? [])
          .map((e) => IntelHighlight.fromJson(e))
          .toList(),
      speciesSummary: (json['speciesSummary'] as List? ?? [])
          .map((e) => SpeciesSummary.fromJson(e))
          .toList(),
      baitStatus: (json['baitStatus'] as List? ?? [])
          .map((e) => BaitStatus.fromJson(e))
          .toList(),
      sourcesUsed: (json['sourcesUsed'] as List? ?? []).cast<String>(),
      dataFreshness: json['dataFreshness'] ?? '',
    );
  }
}

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
  
  String get countDisplay {
    final parts = <String>[];
    if (countKept != null && countKept! > 0) {
      parts.add('$countKept kept');
    }
    if (countReleased != null && countReleased! > 0) {
      parts.add('$countReleased released');
    }
    return parts.isEmpty ? 'reported' : parts.join(' + ');
  }
  
  String get speciesDisplay {
    return species
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
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
  
  String get speciesDisplay {
    return species
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
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
