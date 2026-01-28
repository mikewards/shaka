import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// Custom cache manager for ocean map tiles
/// Tiles are cached for 24 hours to balance freshness with performance
class OceanTileCacheManager {
  static const key = 'oceanTileCache';
  
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(hours: 24),
      maxNrOfCacheObjects: 500, // ~125MB at 256KB per tile
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
  
  /// Clear all cached tiles
  static Future<void> clearCache() async {
    await instance.emptyCache();
  }
}

/// Tile provider that caches tiles to disk for faster subsequent loads
class CachedTileProvider extends TileProvider {
  CachedTileProvider({
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: OceanTileCacheManager.instance,
      headers: headers,
    );
  }
}

/// Image provider that uses flutter_cache_manager for caching
class CachedNetworkImageProvider extends ImageProvider<CachedNetworkImageProvider> {
  final String url;
  final CacheManager cacheManager;
  final Map<String, String> headers;

  const CachedNetworkImageProvider(
    this.url, {
    required this.cacheManager,
    this.headers = const {},
  });

  @override
  Future<CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<String>('URL', url);
      },
    );
  }

  Future<Codec> _loadAsync(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final file = await cacheManager.getSingleFile(
        url,
        headers: headers,
      );
      final bytes = await file.readAsBytes();
      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) {
      // Return transparent tile on error
      final transparentPng = _createTransparentPng();
      final buffer = await ImmutableBuffer.fromUint8List(transparentPng);
      return decode(buffer);
    }
  }

  /// Create a 1x1 transparent PNG for error cases
  Uint8List _createTransparentPng() {
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, // RGBA
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
      0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
      0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
      0xAE, 0x42, 0x60, 0x82,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CachedNetworkImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedNetworkImageProvider("$url")';
}
