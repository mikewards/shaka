import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Represents a downloaded offline region
class OfflineRegion {
  final String id;
  final String name;
  final LatLngBounds bounds;
  final List<String> layerIds; // Which layers are cached
  final int minZoom;
  final int maxZoom;
  final DateTime downloadedAt;
  final DateTime dataDate; // UTC date of the cached data
  final int tileCount;
  final int sizeBytes;
  final DownloadStatus status;

  const OfflineRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.layerIds,
    required this.minZoom,
    required this.maxZoom,
    required this.downloadedAt,
    required this.dataDate,
    required this.tileCount,
    required this.sizeBytes,
    required this.status,
  });

  /// Create from JSON (for persistence)
  factory OfflineRegion.fromJson(Map<String, dynamic> json) {
    return OfflineRegion(
      id: json['id'] as String,
      name: json['name'] as String,
      bounds: LatLngBounds(
        LatLng(json['south'] as double, json['west'] as double),
        LatLng(json['north'] as double, json['east'] as double),
      ),
      layerIds: List<String>.from(json['layerIds'] as List),
      minZoom: json['minZoom'] as int,
      maxZoom: json['maxZoom'] as int,
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      dataDate: DateTime.parse(json['dataDate'] as String),
      tileCount: json['tileCount'] as int,
      sizeBytes: json['sizeBytes'] as int,
      status: DownloadStatus.values.byName(json['status'] as String),
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
      'layerIds': layerIds,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'downloadedAt': downloadedAt.toIso8601String(),
      'dataDate': dataDate.toIso8601String(),
      'tileCount': tileCount,
      'sizeBytes': sizeBytes,
      'status': status.name,
    };
  }

  /// Human-readable size
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Check if data is stale (older than 7 days)
  bool get isStale {
    return DateTime.now().toUtc().difference(dataDate).inDays > 7;
  }

  OfflineRegion copyWith({
    String? id,
    String? name,
    LatLngBounds? bounds,
    List<String>? layerIds,
    int? minZoom,
    int? maxZoom,
    DateTime? downloadedAt,
    DateTime? dataDate,
    int? tileCount,
    int? sizeBytes,
    DownloadStatus? status,
  }) {
    return OfflineRegion(
      id: id ?? this.id,
      name: name ?? this.name,
      bounds: bounds ?? this.bounds,
      layerIds: layerIds ?? this.layerIds,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      dataDate: dataDate ?? this.dataDate,
      tileCount: tileCount ?? this.tileCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      status: status ?? this.status,
    );
  }
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  cancelled,
}

/// Progress information during region download
class RegionDownloadProgress {
  final String regionId;
  final int totalTiles;
  final int downloadedTiles;
  final int failedTiles;
  final int bytesDownloaded;
  final String? currentLayer;
  final int? currentZoom;

  const RegionDownloadProgress({
    required this.regionId,
    required this.totalTiles,
    required this.downloadedTiles,
    this.failedTiles = 0,
    this.bytesDownloaded = 0,
    this.currentLayer,
    this.currentZoom,
  });

  double get progress => totalTiles > 0 ? downloadedTiles / totalTiles : 0;
  
  bool get isComplete => downloadedTiles >= totalTiles;

  String get formattedProgress => '${(progress * 100).toStringAsFixed(1)}%';
}

/// Bounds helper extension
extension LatLngBoundsExt on LatLngBounds {
  double get south => southWest.latitude;
  double get west => southWest.longitude;
  double get north => northEast.latitude;
  double get east => northEast.longitude;
}
