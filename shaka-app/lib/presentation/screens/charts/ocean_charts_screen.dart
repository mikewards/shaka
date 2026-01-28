import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/api/copernicus_wmts_service.dart';
import '../../../data/models/ocean_layer.dart';
import 'widgets/floating_data_bar.dart';
import 'widgets/layer_control_sheet.dart';
import 'widgets/chart_legend.dart';
import 'widgets/point_data_card.dart';

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

  // Selected date for time travel
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));

  // UI state
  bool _showLegend = true;
  String _baseMap = 'dark';

  @override
  void initState() {
    super.initState();

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
  List<TileLayer> _buildTileLayers() {
    final layers = <TileLayer>[];

    // Base map layer
    layers.add(_buildBaseMapLayer());

    // Add enabled ocean data layers
    for (var state in _layerStates.values) {
      if (state.enabled) {
        layers.add(_buildOceanTileLayer(state));
      }
    }

    return layers;
  }

  TileLayer _buildBaseMapLayer() {
    String urlTemplate;
    switch (_baseMap) {
      case 'satellite':
        // Using ESRI World Imagery (free)
        urlTemplate = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
        break;
      case 'nautical':
        // OpenSeaMap nautical layer over OSM
        urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
        break;
      case 'dark':
      default:
        // CartoDB Dark Matter - perfect for ocean visualization
        urlTemplate = 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}@2x.png';
    }

    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'com.shaka.app',
      maxZoom: 18,
      tileProvider: NetworkTileProvider(),
    );
  }

  TileLayer _buildOceanTileLayer(LayerState state) {
    final timeStr = CopernicusWMTSService.formatTime(_selectedDate);

    return TileLayer(
      urlTemplate: CopernicusWMTSService.buildLayerTileUrl(
        state.layer,
        time: timeStr,
      ),
      userAgentPackageName: 'com.shaka.app',
      maxZoom: 10,
      tileProvider: NetworkTileProvider(),
      tileBuilder: (context, tileWidget, tile) {
        // Apply opacity to tiles
        return Opacity(
          opacity: state.opacity,
          child: tileWidget,
        );
      },
      errorTileCallback: (tile, error, stackTrace) {
        // Silently handle tile errors (common for ocean data near coasts)
      },
    );
  }

  /// Update crosshair position and fetch data
  void _onMapMove(MapCamera camera) {
    setState(() {
      _center = camera.center;
      _zoom = camera.zoom;
      _crosshairPosition = camera.center;
    });
  }

  /// Fetch feature data when map stops moving
  void _onMapMoveEnd(MapCamera camera) {
    _fetchFeatureData(camera.center);
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
          });
          if (enabled) _fetchFeatureData(_center);
        },
        onOpacityChange: (layerId, opacity) {
          setState(() {
            _layerStates[layerId] = _layerStates[layerId]!.copyWith(opacity: opacity);
          });
        },
        onBaseMapChange: (baseMap) {
          setState(() => _baseMap = baseMap);
        },
        onDateChange: (date) {
          setState(() => _selectedDate = date);
          _fetchFeatureData(_center);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledLayers = _layerStates.values.where((s) => s.enabled).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: 2,
              maxZoom: 12,
              onPositionChanged: (camera, hasGesture) => _onMapMove(camera),
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  _onMapMoveEnd(_mapController.camera);
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
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolbarButton(
            icon: Icons.layers,
            label: 'Layers',
            onTap: _openLayerControls,
          ),
          _ToolbarButton(
            icon: Icons.calendar_today,
            label: _formatDate(_selectedDate),
            onTap: _openLayerControls,
          ),
          _ToolbarButton(
            icon: _showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
            label: 'Legend',
            onTap: () => setState(() => _showLegend = !_showLegend),
          ),
          _ToolbarButton(
            icon: Icons.share,
            label: 'Share',
            onTap: () {
              // TODO: Implement share
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share coming soon!')),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
