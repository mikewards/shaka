import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/api/copernicus_wmts_service.dart';
import '../../../data/api/cached_tile_provider.dart';
import '../../../data/models/ocean_layer.dart';
import 'widgets/floating_data_bar.dart';
import 'widgets/layer_control_sheet.dart';
import 'widgets/chart_legend.dart';
import 'widgets/point_data_card.dart';
import 'widgets/download_region_sheet.dart';
import 'widgets/offline_regions_sheet.dart';

/// Full-screen immersive ocean charts page
/// Displays oceanographic data overlays (SST, chlorophyll, visibility, etc.)
class OceanChartsScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? initialLayer;

  const OceanChartsScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialLayer,
  });

  @override
  State<OceanChartsScreen> createState() => _OceanChartsScreenState();
}

class _OceanChartsScreenState extends State<OceanChartsScreen> {
  final MapController _mapController = MapController();
  final CopernicusWMTSService _wmtsService = CopernicusWMTSService();

  // Map state
  LatLng _center = const LatLng(21.3, -157.8); // Default: Hawaii
  double _zoom = 6.0;
  LatLng? _crosshairPosition;

  // Layer states
  late Map<String, LayerState> _layerStates;

  // Data at crosshair
  Map<String, FeatureInfo?> _featureData = {};
  bool _isLoadingFeatures = false;

  // Selected date for time travel (stored as UTC)
  // Default to yesterday UTC - Copernicus NRT data has ~24h processing delay
  // All Copernicus data uses UTC timestamps
  late DateTime _selectedDate;

  // UI state
  bool _showLegend = true;
  String _baseMap = 'dark';
  
  // Version counter to force map rebuilds
  int _mapVersion = 0;

  @override
  void initState() {
    super.initState();

    // Initialize selected date to yesterday UTC (Copernicus NRT has ~24h delay)
    // All dates are stored and compared in UTC to match Copernicus timestamps
    final nowUtc = DateTime.now().toUtc();
    _selectedDate = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day - 1);

    // Initialize layer states - SST enabled by default
    _layerStates = {
      for (var layer in OceanLayer.all)
        layer.id: LayerState(
          layer: layer,
          enabled: layer.id == 'sst',
          opacity: 1.0,
        ),
    };

    // Set initial position if provided
    if (widget.initialLat != null && widget.initialLon != null) {
      _center = LatLng(widget.initialLat!, widget.initialLon!);
    }

    // Enable initial layer if specified
    if (widget.initialLayer != null && _layerStates.containsKey(widget.initialLayer)) {
      _layerStates[widget.initialLayer!] = _layerStates[widget.initialLayer!]!.copyWith(enabled: true);
    }

    _crosshairPosition = _center;

    // Make status bar transparent for immersive experience
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Build the list of tile layers based on enabled layers
  List<Widget> _buildTileLayers() {
    final layers = <Widget>[];

    // Base map layer(s)
    layers.addAll(_buildBaseMapLayers());

    // Add enabled ocean data layers
    for (var state in _layerStates.values) {
      if (state.enabled) {
        layers.add(_buildOceanTileLayer(state));
      }
    }

    return layers;
  }

  /// Build base map layers (some styles need multiple layers)
  List<TileLayer> _buildBaseMapLayers() {
    final layers = <TileLayer>[];
    
    // All base maps support zooming up to 18 for crisp land detail
    switch (_baseMap) {
      case 'satellite':
        // ESRI World Imagery - high resolution satellite
        layers.add(TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.shaka.app',
          maxZoom: 18,
          minZoom: 2,
          tileProvider: CachedTileProvider(),
        ));
        // Add labels overlay for better context
        layers.add(TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.shaka.app',
          maxZoom: 18,
          minZoom: 2,
          tileProvider: CachedTileProvider(),
        ));
        break;
        
      case 'nautical':
        // OpenStreetMap standard - high resolution and detailed
        layers.add(TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.shaka.app',
          maxZoom: 18,
          minZoom: 2,
          tileProvider: CachedTileProvider(),
        ));
        // OpenSeaMap overlay for nautical features (buoys, channels, etc.)
        layers.add(TileLayer(
          urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.shaka.app',
          maxZoom: 18,
          minZoom: 2,
          tileProvider: CachedTileProvider(),
        ));
        break;
        
      case 'dark':
      default:
        // CartoDB Dark Matter with retina tiles for HiDPI displays
        layers.add(TileLayer(
          urlTemplate: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
          userAgentPackageName: 'com.shaka.app',
          maxZoom: 18,
          minZoom: 2,
          retinaMode: true,
          tileProvider: CachedTileProvider(),
        ));
    }
    
    return layers;
  }

  TileLayer _buildOceanTileLayer(LayerState state) {
    final timeStr = CopernicusWMTSService.formatTime(_selectedDate);
    
    // GEBCO bathymetry uses WMS (different from Copernicus WMTS)
    if (CopernicusWMTSService.isGebcoLayer(state.layer)) {
      return TileLayer(
        wmsOptions: WMSTileLayerOptions(
          baseUrl: 'https://wms.gebco.net/mapserv?',
          layers: ['gebco_latest_2'],
          transparent: true,
          format: 'image/png',
          version: '1.3.0',
          crs: const Epsg3857(),
        ),
        userAgentPackageName: 'com.shaka.app',
        maxZoom: 18, // Let flutter_map handle zoom > data resolution
        minZoom: 2,
        maxNativeZoom: 10, // Bathymetry data max resolution
        tileProvider: CachedTileProvider(),
        tileBuilder: (context, tileWidget, tile) {
          return Opacity(opacity: state.opacity, child: tileWidget);
        },
        errorTileCallback: (tile, error, stackTrace) {},
      );
    }

    // Standard Copernicus WMTS layers with caching
    // maxNativeZoom limits actual tile requests, beyond that tiles are upscaled
    // This prevents crashes when zooming beyond data resolution
    return TileLayer(
      urlTemplate: CopernicusWMTSService.buildLayerTileUrl(
        state.layer,
        time: timeStr,
      ),
      userAgentPackageName: 'com.shaka.app',
      maxZoom: 18, // Allow map to zoom this far
      minZoom: 2,
      maxNativeZoom: 10, // Copernicus data only goes to zoom 10
      minNativeZoom: 3,
      tileProvider: CachedTileProvider(),
      tileBuilder: (context, tileWidget, tile) {
        return Opacity(opacity: state.opacity, child: tileWidget);
      },
      errorTileCallback: (tile, error, stackTrace) {
        // Silently handle missing tiles (e.g., over land)
      },
    );
  }

  /// Update crosshair position and fetch data
  void _onMapMove(MapPosition position, bool hasGesture) {
    if (position.center != null) {
      setState(() {
        _center = position.center!;
        _zoom = position.zoom ?? _zoom;
        _crosshairPosition = position.center;
      });
    }
  }

  /// Fetch feature data when map stops moving
  void _onMapMoveEnd() {
    _fetchFeatureData(_center);
  }

  Future<void> _fetchFeatureData(LatLng point) async {
    setState(() => _isLoadingFeatures = true);

    final enabledLayers = _layerStates.values.where((s) => s.enabled).toList();
    final newData = <String, FeatureInfo?>{};

    for (var state in enabledLayers) {
      final info = await _wmtsService.getFeatureInfo(
        layer: state.layer,
        point: point,
        time: CopernicusWMTSService.formatTime(_selectedDate),
        zoom: _zoom.round().clamp(4, 10),
      );
      newData[state.layer.id] = info;
    }

    if (mounted) {
      setState(() {
        _featureData = newData;
        _isLoadingFeatures = false;
      });
    }
  }

  /// Handle long press to show detailed point data
  void _onMapLongPress(TapPosition tapPosition, LatLng point) {
    _showPointDataCard(point);
  }

  void _showPointDataCard(LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PointDataCard(
        point: point,
        layerStates: _layerStates.values.where((s) => s.enabled).toList(),
        wmtsService: _wmtsService,
        selectedDate: _selectedDate,
      ),
    );
  }

  /// Open layer control sheet
  void _openLayerControls() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LayerControlSheet(
        layerStates: _layerStates,
        baseMap: _baseMap,
        selectedDate: _selectedDate,
        onLayerToggle: (layerId, enabled) {
          setState(() {
            _layerStates[layerId] = _layerStates[layerId]!.copyWith(enabled: enabled);
            _mapVersion++; // Force map rebuild
          });
          if (enabled) _fetchFeatureData(_center);
        },
        onOpacityChange: (layerId, opacity) {
          setState(() {
            _layerStates[layerId] = _layerStates[layerId]!.copyWith(opacity: opacity);
            _mapVersion++; // Force map rebuild
          });
        },
        onBaseMapChange: (baseMap) {
          setState(() {
            _baseMap = baseMap;
            _mapVersion++; // Force map rebuild
          });
        },
        onDateChange: (date) {
          setState(() {
            _selectedDate = date;
            _mapVersion++; // Force map rebuild
          });
          _fetchFeatureData(_center);
        },
      ),
    );
  }

  /// Open offline download menu
  void _openOfflineMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.white),
              title: const Text('Download This Area', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Save for offline use', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.of(context).pop();
                _openDownloadSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.offline_pin, color: Colors.white),
              title: const Text('Manage Offline Regions', style: TextStyle(color: Colors.white)),
              subtitle: const Text('View and delete saved data', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.of(context).pop();
                _openOfflineRegionsSheet();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Open download region sheet
  void _openDownloadSheet() {
    // Get current visible bounds from the map
    final bounds = _mapController.camera.visibleBounds;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DownloadRegionSheet(
        bounds: bounds,
        dataDate: _selectedDate,
        layerStates: _layerStates,
      ),
    );
  }

  /// Open offline regions management sheet
  void _openOfflineRegionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const OfflineRegionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledLayers = _layerStates.values.where((s) => s.enabled).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen map - use version counter to force rebuilds
          FlutterMap(
            key: ValueKey('map_v$_mapVersion'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: 2,
              maxZoom: 18, // Allow zooming in for detailed base map
              onPositionChanged: _onMapMove,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  _onMapMoveEnd();
                }
              },
              onLongPress: _onMapLongPress,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: _buildTileLayers(),
          ),

          // Crosshair at center
          const Center(
            child: IgnorePointer(
              child: Icon(
                Icons.add,
                color: Colors.white70,
                size: 32,
              ),
            ),
          ),

          // Floating data bar at top
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: FloatingDataBar(
              position: _crosshairPosition,
              featureData: _featureData,
              isLoading: _isLoadingFeatures,
              enabledLayers: enabledLayers,
              onBackPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Legend (collapsible)
          if (_showLegend && enabledLayers.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 100,
              child: ChartLegend(
                enabledLayers: enabledLayers,
                onClose: () => setState(() => _showLegend = false),
              ),
            ),

          // Bottom toolbar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomToolbar(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ToolbarButton(
                icon: Icons.layers,
                label: 'Layers',
                onTap: _openLayerControls,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ToolbarButton(
                icon: Icons.calendar_today,
                label: _formatDate(_selectedDate),
                onTap: _openLayerControls,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ToolbarButton(
                icon: _showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
                label: 'Legend',
                onTap: () => setState(() => _showLegend = !_showLegend),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ToolbarButton(
                icon: Icons.download_for_offline,
                label: 'Offline',
                onTap: _openOfflineMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[utc.month - 1]} ${utc.day} UTC';
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
