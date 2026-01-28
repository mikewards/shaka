import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../data/models/ocean_layer.dart';
import '../../../../data/models/offline_region.dart';
import '../../../../data/services/offline_download_service.dart';

/// Bottom sheet for downloading a region for offline use
class DownloadRegionSheet extends StatefulWidget {
  final LatLngBounds bounds;
  final DateTime dataDate;
  final Map<String, LayerState> layerStates;

  const DownloadRegionSheet({
    super.key,
    required this.bounds,
    required this.dataDate,
    required this.layerStates,
  });

  @override
  State<DownloadRegionSheet> createState() => _DownloadRegionSheetState();
}

class _DownloadRegionSheetState extends State<DownloadRegionSheet> {
  final _nameController = TextEditingController();
  final _downloadService = OfflineDownloadService();
  
  late Set<String> _selectedLayerIds;
  int _minZoom = 4;
  int _maxZoom = 8;
  
  bool _isDownloading = false;
  RegionDownloadProgress? _progress;
  StreamSubscription<RegionDownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    // Pre-select currently enabled layers
    _selectedLayerIds = widget.layerStates.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toSet();
    
    _nameController.text = _generateRegionName();
    
    _progressSub = _downloadService.progressStream.listen((progress) {
      setState(() => _progress = progress);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _progressSub?.cancel();
    _downloadService.dispose();
    super.dispose();
  }

  String _generateRegionName() {
    final center = LatLng(
      (widget.bounds.south + widget.bounds.north) / 2,
      (widget.bounds.west + widget.bounds.east) / 2,
    );
    return 'Region ${center.latitude.toStringAsFixed(1)}, ${center.longitude.toStringAsFixed(1)}';
  }

  int get _estimatedTiles {
    return OfflineDownloadService.calculateTileCount(
      bounds: widget.bounds,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    ) * (1 + _selectedLayerIds.length);
  }

  String get _estimatedSize {
    final bytes = OfflineDownloadService.estimateSize(
      bounds: widget.bounds,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      layerCount: _selectedLayerIds.length,
    );
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  Future<void> _startDownload() async {
    if (_selectedLayerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one layer')),
      );
      return;
    }

    setState(() => _isDownloading = true);

    final layers = OceanLayer.all
        .where((l) => _selectedLayerIds.contains(l.id))
        .toList();

    try {
      final region = await _downloadService.downloadRegion(
        name: _nameController.text,
        bounds: widget.bounds,
        layers: layers,
        dataDate: widget.dataDate,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
      );

      if (mounted) {
        Navigator.of(context).pop(region);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              region.status == DownloadStatus.completed
                  ? 'Downloaded ${region.formattedSize}'
                  : 'Download incomplete',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _cancelDownload() {
    _downloadService.cancelDownload();
    setState(() => _isDownloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.download_for_offline, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Download for Offline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_isDownloading) ...[
              _buildDownloadProgress(),
            ] else ...[
              // Region name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Region Name',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Zoom range
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DETAIL LEVEL',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildZoomChip('Low', 4, 6),
                        const SizedBox(width: 8),
                        _buildZoomChip('Medium', 4, 8),
                        const SizedBox(width: 8),
                        _buildZoomChip('High', 4, 10),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Layer selection
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LAYERS TO DOWNLOAD',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...OceanLayer.all.take(6).map((layer) => _buildLayerToggle(layer)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Estimate
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Size',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          Text(
                            _estimatedSize,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_estimatedTiles} tiles',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          '${_selectedLayerIds.length} layers',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Download button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedLayerIds.isNotEmpty ? _startDownload : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Download Region',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoomChip(String label, int min, int max) {
    final isSelected = _minZoom == min && _maxZoom == max;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _minZoom = min;
          _maxZoom = max;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white24,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerToggle(OceanLayer layer) {
    final isSelected = _selectedLayerIds.contains(layer.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedLayerIds.remove(layer.id);
          } else {
            _selectedLayerIds.add(layer.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(layer.icon, color: isSelected ? layer.color : Colors.white24, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                layer.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white24,
                  width: 2,
                ),
                color: isSelected ? Colors.white : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Progress circle
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress?.progress ?? 0,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      progress?.formattedProgress ?? '0%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (progress != null)
                      Text(
                        '${progress.downloadedTiles}/${progress.totalTiles}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Current status
          if (progress != null) ...[
            Text(
              'Downloading ${progress.currentLayer ?? "..."}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (progress.currentZoom != null)
              Text(
                'Zoom level ${progress.currentZoom}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],

          const SizedBox(height: 24),

          // Cancel button
          TextButton(
            onPressed: _cancelDownload,
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
