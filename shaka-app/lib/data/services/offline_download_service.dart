import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/copernicus_wmts_service.dart';
import '../models/ocean_layer.dart';
import '../models/offline_region.dart';

/// Service for downloading and managing offline map regions
class OfflineDownloadService {
  static const String _regionsKey = 'offline_regions';
  static const int _maxConcurrentDownloads = 4;
  
  final CacheManager _cacheManager;
  final _progressController = StreamController<RegionDownloadProgress>.broadcast();
  
  bool _isCancelled = false;
  String? _currentDownloadId;

  OfflineDownloadService({CacheManager? cacheManager})
      : _cacheManager = cacheManager ?? DefaultCacheManager();

  /// Stream of download progress updates
  Stream<RegionDownloadProgress> get progressStream => _progressController.stream;

  /// Calculate number of tiles for a region
  static int calculateTileCount({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
  }) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final tiles = _getTilesInBounds(bounds, z);
      total += tiles.length;
    }
    return total;
  }

  /// Estimate download size in bytes (rough estimate: ~50KB per tile average)
  static int estimateSize({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required int layerCount,
  }) {
    final tileCount = calculateTileCount(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    // Base map ~30KB, each data layer ~50KB per tile
    return tileCount * (30000 + (layerCount * 50000));
  }

  /// Download tiles for a region
  Future<OfflineRegion> downloadRegion({
    required String name,
    required LatLngBounds bounds,
    required List<OceanLayer> layers,
    required DateTime dataDate,
    int minZoom = 4,
    int maxZoom = 10,
  }) async {
    _isCancelled = false;
    
    final regionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentDownloadId = regionId;
    
    final timeStr = CopernicusWMTSService.formatTime(dataDate);
    int downloadedTiles = 0;
    int failedTiles = 0;
    int bytesDownloaded = 0;
    
    // Calculate total tiles (base map + data layers)
    final baseTileCount = calculateTileCount(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    final totalTiles = baseTileCount * (1 + layers.length); // Base + each layer

    // Download base map tiles first
    for (int z = minZoom; z <= maxZoom && !_isCancelled; z++) {
      final tiles = _getTilesInBounds(bounds, z);
      
      for (final batch in _batchList(tiles, _maxConcurrentDownloads)) {
        if (_isCancelled) break;
        
        await Future.wait(batch.map((tile) async {
          try {
            final url = 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/${tile.z}/${tile.x}/${tile.y}@2x.png';
            final file = await _cacheManager.downloadFile(url);
            bytesDownloaded += await file.file.length();
            downloadedTiles++;
          } catch (e) {
            failedTiles++;
          }
          
          _progressController.add(RegionDownloadProgress(
            regionId: regionId,
            totalTiles: totalTiles,
            downloadedTiles: downloadedTiles,
            failedTiles: failedTiles,
            bytesDownloaded: bytesDownloaded,
            currentLayer: 'Base Map',
            currentZoom: z,
          ));
        }));
      }
    }

    // Download data layer tiles
    for (final layer in layers) {
      if (_isCancelled) break;
      
      for (int z = minZoom; z <= maxZoom && !_isCancelled; z++) {
        final tiles = _getTilesInBounds(bounds, z);
        
        for (final batch in _batchList(tiles, _maxConcurrentDownloads)) {
          if (_isCancelled) break;
          
          await Future.wait(batch.map((tile) async {
            try {
              final url = _buildTileUrl(layer, tile, timeStr);
              final file = await _cacheManager.downloadFile(url);
              bytesDownloaded += await file.file.length();
              downloadedTiles++;
            } catch (e) {
              failedTiles++;
            }
            
            _progressController.add(RegionDownloadProgress(
              regionId: regionId,
              totalTiles: totalTiles,
              downloadedTiles: downloadedTiles,
              failedTiles: failedTiles,
              bytesDownloaded: bytesDownloaded,
              currentLayer: layer.name,
              currentZoom: z,
            ));
          }));
        }
      }
    }

    final region = OfflineRegion(
      id: regionId,
      name: name,
      bounds: bounds,
      layerIds: layers.map((l) => l.id).toList(),
      minZoom: minZoom,
      maxZoom: maxZoom,
      downloadedAt: DateTime.now(),
      dataDate: dataDate,
      tileCount: downloadedTiles,
      sizeBytes: bytesDownloaded,
      status: _isCancelled 
          ? DownloadStatus.cancelled 
          : (failedTiles > totalTiles * 0.1 
              ? DownloadStatus.failed 
              : DownloadStatus.completed),
    );

    // Save region metadata
    await _saveRegion(region);
    
    _currentDownloadId = null;
    return region;
  }

  /// Cancel current download
  void cancelDownload() {
    _isCancelled = true;
  }

  /// Get all saved regions
  Future<List<OfflineRegion>> getRegions() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_regionsKey);
    if (json == null) return [];
    
    final list = jsonDecode(json) as List;
    return list.map((e) => OfflineRegion.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Delete a region and its cached tiles
  Future<void> deleteRegion(String regionId) async {
    final regions = await getRegions();
    final updated = regions.where((r) => r.id != regionId).toList();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_regionsKey, jsonEncode(updated.map((r) => r.toJson()).toList()));
    
    // Note: We can't easily delete specific tiles from cache
    // The cache will naturally expire old tiles
  }

  /// Clear all offline data
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_regionsKey);
    await _cacheManager.emptyCache();
  }

  Future<void> _saveRegion(OfflineRegion region) async {
    final regions = await getRegions();
    final existingIndex = regions.indexWhere((r) => r.id == region.id);
    
    if (existingIndex >= 0) {
      regions[existingIndex] = region;
    } else {
      regions.add(region);
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_regionsKey, jsonEncode(regions.map((r) => r.toJson()).toList()));
  }

  String _buildTileUrl(OceanLayer layer, TileCoord tile, String time) {
    final encodedStyle = Uri.encodeComponent(layer.style);
    return 'https://wmts.marine.copernicus.eu/teroWmts'
        '?service=WMTS'
        '&version=1.0.0'
        '&request=GetTile'
        '&layer=${layer.wmtsLayer}'
        '&tilematrixset=EPSG:3857@2x'
        '&tilematrix=${tile.z}'
        '&tilerow=${tile.y}'
        '&tilecol=${tile.x}'
        '&format=image/png'
        '&STYLE=$encodedStyle'
        '&time=$time';
  }

  /// Get all tiles within bounds at a zoom level
  static List<TileCoord> _getTilesInBounds(LatLngBounds bounds, int zoom) {
    final tiles = <TileCoord>[];
    
    final minTile = _latLngToTile(bounds.southWest, zoom);
    final maxTile = _latLngToTile(bounds.northEast, zoom);
    
    // Handle tile wrapping
    final minX = math.min(minTile.x, maxTile.x);
    final maxX = math.max(minTile.x, maxTile.x);
    final minY = math.min(minTile.y, maxTile.y);
    final maxY = math.max(minTile.y, maxTile.y);
    
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        tiles.add(TileCoord(x, y, zoom));
      }
    }
    
    return tiles;
  }

  /// Convert lat/lng to tile coordinates (Web Mercator)
  static TileCoord _latLngToTile(LatLng point, int zoom) {
    final n = math.pow(2, zoom).toInt();
    final x = ((point.longitude + 180) / 360 * n).floor();
    final latRad = point.latitude * math.pi / 180;
    final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
    return TileCoord(x.clamp(0, n - 1), y.clamp(0, n - 1), zoom);
  }

  /// Split list into batches
  static List<List<T>> _batchList<T>(List<T> list, int batchSize) {
    final batches = <List<T>>[];
    for (var i = 0; i < list.length; i += batchSize) {
      batches.add(list.sublist(i, math.min(i + batchSize, list.length)));
    }
    return batches;
  }

  void dispose() {
    _progressController.close();
  }
}

/// Simple tile coordinate
class TileCoord {
  final int x;
  final int y;
  final int z;
  
  const TileCoord(this.x, this.y, this.z);
}
