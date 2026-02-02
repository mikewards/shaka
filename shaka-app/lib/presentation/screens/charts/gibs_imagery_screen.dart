import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../data/api/gibs_service.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/gibs_layer.dart';
import '../../../data/models/spot_models.dart';
import '../../../data/services/map_background_service.dart';
import '../../widgets/dynamic_ocean_legend.dart';
import '../../widgets/background_picker.dart';
import '../../widgets/save_spot_sheet.dart';

/// GIBS Satellite Imagery Screen
/// Uses MapLibre GL to display NASA GIBS satellite imagery layers
class GibsImageryScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final String? spotName;
  
  const GibsImageryScreen({
    super.key,
    this.initialLat,
    this.initialLon,
    this.spotName,
  });

  @override
  State<GibsImageryScreen> createState() => _GibsImageryScreenState();
}

class _GibsImageryScreenState extends State<GibsImageryScreen> {
  MaplibreMapController? _mapController;
  final MapBackgroundService _bgService = MapBackgroundService();
  
  // Active layers (supports multiple for stacking)
  // Default to Full Coverage preset for maximum satellite coverage
  List<GibsLayer> _activeLayers = GibsLayerPreset.fullCoverage.layers;
  
  // Currently active preset (null if custom selection)
  GibsLayerPreset? _activePreset = GibsLayerPreset.fullCoverage;
  
  // Selected date (defaults to yesterday for data availability)
  late DateTime _selectedDate;
  
  // Layer opacity
  double _opacity = 1.0;
  
  // Loading state
  bool _isLoading = true;
  
  // Date validation warning message
  String? _dateWarning;
  
  // Map center (default: Hawaii, or from spot if provided)
  late LatLng _initialCenter;
  static const _defaultZoom = 5.0;
  static const _spotZoom = 8.0; // Closer zoom when viewing a spot
  
  // Key to force map rebuild when background changes
  int _mapKey = 0;
  
  // Store camera position to restore after style change
  CameraPosition? _lastCameraPosition;
  
  // Pin mode state
  bool _isPinMode = false;
  LatLng? _currentCenter;
  
  // Saved spots state
  final ShakaApiClient _apiClient = ShakaApiClient();
  List<UserSpotResponse> _savedSpots = [];
  bool _showSpotsOnMap = false;
  
  // Helper getters
  bool get _hasMultipleLayers => _activeLayers.length > 1;
  GibsLayer get _primaryLayer => _activeLayers.first;

  @override
  void initState() {
    super.initState();
    _selectedDate = GibsService.yesterdayUtc;
    _bgService.addListener(_onBackgroundChanged);
    
    // Set initial center from spot coordinates or default to Catalina Islands, CA
    _initialCenter = (widget.initialLat != null && widget.initialLon != null)
        ? LatLng(widget.initialLat!, widget.initialLon!)
        : const LatLng(33.4, -118.4);
    
    // Immersive status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    
    _loadSavedSpots();
  }
  
  void _onBackgroundChanged() {
    // Save current camera position before rebuilding map
    if (_mapController != null) {
      _lastCameraPosition = _mapController!.cameraPosition;
    }
    _mapController = null;
    setState(() {
      _mapKey++;
      _isLoading = true;
    });
  }
  
  // Check if opened from a spot
  bool get _hasSpotContext => widget.spotName != null;

  @override
  void dispose() {
    _bgService.removeListener(_onBackgroundChanged);
    _mapController = null;
    super.dispose();
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
    // Note: Layers are added in _onStyleLoaded, not here
  }

  void _onCameraMove() {
    if (_isPinMode && _mapController != null) {
      final position = _mapController!.cameraPosition;
      if (position != null) {
        setState(() {
          _currentCenter = position.target;
        });
      }
    }
  }

  void _onStyleLoaded() async {
    // First add background overlays (satellite, terrain, etc.)
    await _addBackgroundOverlays();
    
    // Then add GIBS layers on top
    await _addGibsLayers();
    
    setState(() => _isLoading = false);
    
    // Add spot marker if opened from a spot
    if (_hasSpotContext) {
      _addSpotMarker();
    }
    
    // Re-add spot markers when map style changes
    if (_showSpotsOnMap && _savedSpots.isNotEmpty) {
      await _updateSpotMarkers();
    }
  }
  
  /// Add background overlays based on selected map style
  Future<void> _addBackgroundOverlays() async {
    if (_mapController == null) return;
    
    final overlays = _bgService.getOverlays(_bgService.current);
    
    for (final overlay in overlays) {
      try {
        // Remove existing if present
        try {
          await _mapController!.removeLayer('${overlay.id}-layer');
          await _mapController!.removeSource(overlay.id);
        } catch (_) {}
        
        await _mapController!.addSource(
          overlay.id,
          RasterSourceProperties(
            tiles: [overlay.urlTemplate],
            tileSize: overlay.tileSize.toDouble(),
            minzoom: overlay.minZoom,
            maxzoom: overlay.maxZoom,
          ),
        );
        
        await _mapController!.addRasterLayer(
          overlay.id,
          '${overlay.id}-layer',
          RasterLayerProperties(rasterOpacity: overlay.opacity),
        );
      } catch (e) {
        debugPrint('Failed to add background overlay ${overlay.id}: $e');
      }
    }
  }
  
  /// Add a marker for the spot location - pin style with outer glow
  Future<void> _addSpotMarker() async {
    if (_mapController == null || !_hasSpotContext) return;
    
    try {
      // Outer glow ring (larger, semi-transparent)
      await _mapController!.addCircle(
        CircleOptions(
          geometry: _initialCenter,
          circleRadius: 24,
          circleColor: '#00BCD4',
          circleStrokeColor: '#00BCD4',
          circleStrokeWidth: 2,
          circleOpacity: 0.15,
        ),
      );
      
      // Middle ring (white border)
      await _mapController!.addCircle(
        CircleOptions(
          geometry: _initialCenter,
          circleRadius: 14,
          circleColor: '#FFFFFF',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 0,
          circleOpacity: 1.0,
        ),
      );
      
      // Inner dot (cyan accent - matches app theme)
      await _mapController!.addCircle(
        CircleOptions(
          geometry: _initialCenter,
          circleRadius: 10,
          circleColor: '#00BCD4',
          circleStrokeColor: '#00838F',
          circleStrokeWidth: 2,
          circleOpacity: 1.0,
        ),
      );
      
      // Center dot (white)
      await _mapController!.addCircle(
        CircleOptions(
          geometry: _initialCenter,
          circleRadius: 4,
          circleColor: '#FFFFFF',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 0,
          circleOpacity: 1.0,
        ),
      );
    } catch (e) {
      // Ignore marker errors - non-critical feature
      debugPrint('Could not add spot marker: $e');
    }
  }

  // Prevent concurrent layer additions
  bool _isAddingLayers = false;
  
  /// Add GIBS raster layers to the map (supports multiple stacked layers)
  Future<void> _addGibsLayers() async {
    if (_mapController == null) return;
    
    // Prevent concurrent calls
    if (_isAddingLayers) {
      debugPrint('GIBS: Skipping duplicate _addGibsLayers call');
      return;
    }
    _isAddingLayers = true;

    final dateStr = GibsService.formatDate(_selectedDate);

    // Check date validation for primary layer
    setState(() {
      _dateWarning = GibsService.getDateValidationMessage(_primaryLayer, _selectedDate);
    });

    try {
      // Remove all existing GIBS sources and layers
      for (int i = 0; i < 10; i++) {
        try {
          await _mapController!.removeLayer('gibs-layer-$i');
        } catch (_) {}
        try {
          await _mapController!.removeSource('gibs-source-$i');
        } catch (_) {}
      }
      // Also remove old single layer format if exists
      try {
        await _mapController!.removeLayer('gibs-layer');
      } catch (_) {}
      try {
        await _mapController!.removeSource('gibs-source');
      } catch (_) {}
      
      // Small delay to let removals complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Add layers in reverse order (bottom first, top last)
      // This way, the first layer in _activeLayers (highest priority) ends up on top
      final reversedLayers = _activeLayers.reversed.toList();
      for (int i = 0; i < reversedLayers.length; i++) {
        final layer = reversedLayers[i];
        final tileUrl = GibsService.buildTileUrlWithFormat(layer, time: dateStr);
        
        debugPrint('GIBS Layer $i: ${layer.shortName} - $tileUrl');
        
        await _mapController!.addSource(
          'gibs-source-$i',
          RasterSourceProperties(
            tiles: [tileUrl],
            tileSize: 256,
            maxzoom: layer.maxZoom.toDouble(),
          ),
        );

        await _mapController!.addRasterLayer(
          'gibs-source-$i',
          'gibs-layer-$i',
          RasterLayerProperties(
            rasterOpacity: _opacity,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error adding GIBS layers: $e');
    } finally {
      _isAddingLayers = false;
    }
  }
  
  // Legacy method name for compatibility
  Future<void> _addGibsLayer() => _addGibsLayers();

  /// Update layer opacity (applies to all active layers)
  Future<void> _updateOpacity(double opacity) async {
    setState(() => _opacity = opacity);
    
    if (_mapController != null) {
      // Update opacity for all active layers
      for (int i = 0; i < _activeLayers.length; i++) {
        try {
          await _mapController!.setLayerProperties(
            'gibs-layer-$i',
            RasterLayerProperties(rasterOpacity: opacity),
          );
        } catch (e) {
          debugPrint('Error updating opacity for layer $i: $e');
        }
      }
    }
  }

  /// Set active layers (replaces all current layers)
  void _setLayers(List<GibsLayer> layers, {GibsLayerPreset? preset}) async {
    if (layers.isEmpty) return;
    
    setState(() {
      _activeLayers = layers;
      _activePreset = preset;
      _isLoading = true;
      _dateWarning = null;
    });
    _addGibsLayers().then((_) {
      setState(() => _isLoading = false);
    });
  }
  
  /// Toggle a single layer on/off
  void _toggleLayer(GibsLayer layer) {
    final isActive = _activeLayers.any((l) => l.id == layer.id);
    List<GibsLayer> newLayers;
    
    if (isActive) {
      // Remove layer (but keep at least one)
      newLayers = _activeLayers.where((l) => l.id != layer.id).toList();
      if (newLayers.isEmpty) return; // Don't allow empty selection
    } else {
      // Add layer
      newLayers = [..._activeLayers, layer];
    }
    
    _setLayers(newLayers, preset: null); // Clear preset when manually toggling
  }
  
  /// Apply a preset
  void _applyPreset(GibsLayerPreset preset) {
    _setLayers(preset.layers, preset: preset);
  }

  /// Change date
  void _changeDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isLoading = true;
      _dateWarning = null;
    });
    _addGibsLayers().then((_) {
      setState(() => _isLoading = false);
    });
  }

  /// Show layer picker bottom sheet
  void _showLayerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LayerPickerSheet(
        initialActiveLayers: List.from(_activeLayers),
        initialActivePreset: _activePreset,
        onSelectionChanged: (layers, preset) {
          _setLayers(layers, preset: preset);
        },
      ),
    );
  }

  // ===========================================
  // PIN MODE METHODS
  // ===========================================

  void _enterPinMode() {
    final center = _mapController?.cameraPosition?.target;
    setState(() {
      _isPinMode = true;
      _currentCenter = center;
    });
    HapticFeedback.mediumImpact();
  }

  void _exitPinMode() {
    setState(() {
      _isPinMode = false;
      _currentCenter = null;
    });
  }

  Future<void> _confirmPinLocation() async {
    if (_currentCenter == null) return;
    
    final saved = await SaveSpotSheet.show(
      context: context,
      latitude: _currentCenter!.latitude,
      longitude: _currentCenter!.longitude,
    );
    
    if (saved && mounted) {
      _exitPinMode();
      await _loadSavedSpots();  // Refresh list after save
    }
  }

  // ===========================================
  // SAVED SPOTS METHODS
  // ===========================================

  Future<void> _loadSavedSpots() async {
    try {
      final response = await _apiClient.getUserSpots();
      if (mounted) {
        setState(() {
          _savedSpots = response.spots;
        });
        if (_showSpotsOnMap && _savedSpots.isNotEmpty) {
          await _updateSpotMarkers();
        }
      }
    } catch (e) {
      debugPrint('Failed to load saved spots: $e');
    }
  }

  Future<void> _updateSpotMarkers() async {
    if (_mapController == null || _savedSpots.isEmpty) return;
    
    await _removeSpotMarkers();
    
    // CRITICAL: Check controller after each await (prevents crashes)
    if (_mapController == null) return;
    
    // Build GeoJSON FeatureCollection
    final features = _savedSpots.map((spot) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [spot.longitude, spot.latitude],
      },
      'properties': {
        'name': spot.name,
        'id': spot.id,
      },
    }).toList();
    
    final geojson = {
      'type': 'FeatureCollection',
      'features': features,
    };
    
    if (_mapController == null) return;
    
    // Add source
    await _mapController!.addSource(
      'saved-spots-source',
      GeojsonSourceProperties(data: geojson),
    );
    
    if (_mapController == null) return;
    
    // Add circle layer (green markers)
    await _mapController!.addCircleLayer(
      'saved-spots-source',
      'saved-spots-layer',
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: '#6B8E7D',  // Sage green (AppColors.scoreExcellent)
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    
    if (_mapController == null) return;
    
    // Add labels
    await _mapController!.addSymbolLayer(
      'saved-spots-source',
      'saved-spots-labels',
      const SymbolLayerProperties(
        textField: ['get', 'name'],
        textSize: 11,
        textColor: '#FFFFFF',
        textHaloColor: '#000000',
        textHaloWidth: 1,
        textOffset: [0, 1.5],
      ),
    );
  }

  Future<void> _removeSpotMarkers() async {
    try { await _mapController?.removeLayer('saved-spots-labels'); } catch (_) {}
    try { await _mapController?.removeLayer('saved-spots-layer'); } catch (_) {}
    try { await _mapController?.removeSource('saved-spots-source'); } catch (_) {}
  }

  void _showSavedSpotsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header with toggle
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text(
                            'Saved Spots',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                _showSpotsOnMap = !_showSpotsOnMap;
                              });
                              setState(() {});
                              if (_showSpotsOnMap) {
                                _updateSpotMarkers();
                              } else {
                                _removeSpotMarkers();
                              }
                            },
                            child: Row(
                              children: [
                                Icon(
                                  _showSpotsOnMap ? Icons.visibility : Icons.visibility_off,
                                  color: _showSpotsOnMap ? const Color(0xFF6B8E7D) : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Show on map',
                                  style: TextStyle(
                                    color: _showSpotsOnMap ? const Color(0xFF6B8E7D) : Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Spot list
                    Expanded(
                      child: _savedSpots.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bookmark_border, color: Colors.white24, size: 48),
                                  SizedBox(height: 12),
                                  Text(
                                    'No saved spots yet',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Tap the + button to save a location',
                                    style: TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _savedSpots.length,
                              itemBuilder: (context, index) {
                                final spot = _savedSpots[index];
                                return _SavedSpotCard(
                                  spot: spot,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _navigateToSpotDetail(spot);
                                  },
                                  onDelete: () async {
                                    await _deleteSpot(spot, setModalState);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _navigateToSpotDetail(UserSpotResponse spot) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {
      'date': today,
      'isUserSpot': true,
    });
  }

  Future<void> _deleteSpot(UserSpotResponse spot, StateSetter setModalState) async {
    try {
      await _apiClient.deleteUserSpot(spot.id);
      setModalState(() {
        _savedSpots.removeWhere((s) => s.id == spot.id);
      });
      setState(() {});
      if (_showSpotsOnMap) {
        await _updateSpotMarkers();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${spot.name}"'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete spot'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Show date picker
  void _showDatePicker() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2012, 1, 1), // GIBS has data from ~2012
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF5B9BD5),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
              secondary: Color(0xFF5B9BD5),
              onSecondary: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF5B9BD5), // Bright Cancel/OK buttons
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      _changeDate(picked);
    }
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // MapLibre Map - keyed to rebuild on background change
          // Wrapped in Listener to detect pan gestures for continuous coordinate updates
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (event) {
              if (_isPinMode && _mapController != null) {
                // Poll camera position during drag for real-time coordinate updates
                final pos = _mapController!.cameraPosition;
                if (pos != null && (_currentCenter == null || 
                    pos.target.latitude != _currentCenter!.latitude ||
                    pos.target.longitude != _currentCenter!.longitude)) {
                  setState(() => _currentCenter = pos.target);
                }
              }
            },
            child: MaplibreMap(
              key: ValueKey('gibs_map_$_mapKey'),
              styleString: _bgService.getStyleUrl(_bgService.current),
              initialCameraPosition: _lastCameraPosition ?? CameraPosition(
                target: _initialCenter,
                zoom: _hasSpotContext ? _spotZoom : _defaultZoom,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              trackCameraPosition: true,
              onCameraIdle: _onCameraMove,
              compassEnabled: false,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: false,
              myLocationEnabled: false,
              attributionButtonMargins: const Point(-100, -100),
              logoViewMargins: const Point(-100, -100),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // GPS Coordinates Display (top-left when in pin mode)
          if (_isPinMode && _currentCenter != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentCenter!.latitude.toStringAsFixed(5)}, ${_currentCenter!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Reticle Crosshairs (center when in pin mode)
          if (_isPinMode)
            const Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(painter: _ReticlePainter()),
              ),
            ),

          // Top bar with back button and layer info (hidden in pin mode)
          if (!_isPinMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: _buildTopBar(),
            ),

          // Floating action buttons on map (left side - vertically stacked)
          if (!_isPinMode)
            Positioned(
              left: 16,
              bottom: MediaQuery.of(context).padding.bottom + 140,
              child: _buildFloatingButtons(),
            ),

          // Bottom controls (opacity/legend only)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        // Back button - floating pill style
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        const Spacer(),
        // Date and satellite info - floating pill (tappable to change date)
        GestureDetector(
          onTap: _showDatePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Satellite color dots
                if (_hasMultipleLayers)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 20 + (_activeLayers.length.clamp(0, 3) - 1) * 6.0,
                      height: 14,
                      child: Stack(
                        children: [
                          for (int i = 0; i < _activeLayers.length.clamp(0, 3); i++)
                            Positioned(
                              left: i * 6.0,
                              top: 1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _activeLayers[i].color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black54, width: 1),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _primaryLayer.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Date (and spot name if available)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasSpotContext)
                      Text(
                        widget.spotName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      _formatDate(_selectedDate),
                      style: TextStyle(
                        color: _hasSpotContext ? Colors.white70 : Colors.white,
                        fontSize: _hasSpotContext ? 11 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Date warning (if applicable)
          _buildDateWarning(),
          
          // Opacity slider and legend on SAME row (50/50 split)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Opacity slider (~50% width)
              Expanded(
                flex: 1,
                child: _buildOpacityRow(),
              ),
              const SizedBox(width: 12),
              // Legend(s) (~50% width)
              Expanded(
                flex: 1,
                child: _buildCompactLegends(),
              ),
            ],
          ),
          
          // Pin mode action buttons (inside container when active)
          if (_isPinMode) ...[
            const SizedBox(height: 12),
            _buildPinModeActions(),
          ],
        ],
      ),
    );
  }
  
  /// Floating buttons on the map (vertically stacked)
  Widget _buildFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Layers button
        _buildFloatingButton(
          icon: Icons.layers_outlined,
          onTap: _showLayerPicker,
        ),
        const SizedBox(height: 8),
        // Map style button
        _buildFloatingButton(
          icon: Icons.map_outlined,
          onTap: () => showBackgroundPicker(context),
        ),
        const SizedBox(height: 8),
        // Add spot button (enters pin mode)
        _buildFloatingButton(
          icon: Icons.add_location_alt,
          onTap: _enterPinMode,
        ),
        const SizedBox(height: 8),
        // Saved spots button with badge
        _buildFloatingButton(
          icon: Icons.bookmark_outline,
          onTap: _showSavedSpotsSheet,
          badgeCount: _savedSpots.length,
        ),
      ],
    );
  }
  
  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            if (badgeCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF5B9BD5),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// Build pin mode cancel/mark spot buttons (inside bottom container)
  Widget _buildPinModeActions() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _exitPinMode,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: const Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _confirmPinLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Mark Spot',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  /// Build horizontal date selector showing recent days
  Widget _buildDateSelector() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    
    // Generate 7 days: 6 days ago to today (GIBS is daily, usually yesterday or earlier)
    final dates = List.generate(7, (i) {
      return todayDate.subtract(Duration(days: 6 - i));
    });
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: dates.map((date) {
          final isSelected = _selectedDate.year == date.year && 
                            _selectedDate.month == date.month && 
                            _selectedDate.day == date.day;
          
          // Format: "Mon" for weekday, "28" for day
          const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final weekday = weekdays[date.weekday - 1];
          final dayNum = date.day.toString();
          
          // Check if date is in the future (no data available)
          final isFuture = date.isAfter(todayDate);
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: isFuture ? null : () => _changeDate(date),
              child: Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryLayer.color : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected 
                        ? _primaryLayer.color 
                        : (isFuture ? Colors.white12 : Colors.white24),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekday,
                      style: TextStyle(
                        color: isFuture 
                            ? Colors.white24 
                            : (isSelected ? Colors.white : Colors.white70),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayNum,
                      style: TextStyle(
                        color: isFuture 
                            ? Colors.white24 
                            : (isSelected ? Colors.white : Colors.white),
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  /// Build compact legend(s) for active layers using unified DynamicOceanLegend
  /// Returns legends for each unique category with hasLegend
  Widget _buildCompactLegends() {
    // Get unique categories with legends from active layers
    final categoriesWithLegends = <GibsLayerCategory, GibsLayer>{};
    for (final layer in _activeLayers) {
      if (layer.hasLegend && !categoriesWithLegends.containsKey(layer.category)) {
        categoriesWithLegends[layer.category] = layer;
      }
    }
    
    if (categoriesWithLegends.isEmpty) return const SizedBox.shrink();
    
    // Stack legends vertically for each category
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: categoriesWithLegends.values.map((layer) {
        // Get category display name
        final categoryName = layer.category == GibsLayerCategory.chlorophyll 
            ? 'Chl-a'  // Standard scientific abbreviation
            : layer.category == GibsLayerCategory.seaSurfaceTemp 
                ? 'SST' 
                : '';
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: DynamicOceanLegend.fromGibs(
            colors: layer.legendColors!,
            labels: layer.legendLabels!,
            unit: layer.legendUnit,
            categoryName: categoryName,
            compact: true,
          ),
        );
      }).toList(),
    );
  }
  
  /// Build compact opacity slider row
  Widget _buildOpacityRow() {
    return Row(
      children: [
        const Icon(Icons.opacity, color: Colors.white54, size: 16),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3),
            child: Slider(
              value: _opacity,
              activeColor: _primaryLayer.color,
              inactiveColor: Colors.white24,
              onChanged: _updateOpacity,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(_opacity * 100).round()}%',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ],
    );
  }
  
  
  void _showBackgroundPicker() {
    showBackgroundPicker(context);
  }
  
  /// Build date warning widget
  Widget _buildDateWarning() {
    if (_dateWarning == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _dateWarning!,
              style: const TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _showLayerInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Row(
              children: [
                Icon(
                  _hasMultipleLayers ? Icons.layers : _primaryLayer.icon, 
                  color: _hasMultipleLayers ? Colors.blue : _primaryLayer.color, 
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasMultipleLayers 
                            ? (_activePreset?.name ?? '${_activeLayers.length} Satellites')
                            : _primaryLayer.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_hasMultipleLayers && _primaryLayer.satellite != null)
                        Text(
                          _primaryLayer.satellite!,
                          style: TextStyle(
                            color: _primaryLayer.color,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Content based on single/multi layer
            if (_hasMultipleLayers) ...[
              Text(
                _activePreset?.description ?? 'Multiple satellite layers combined for better coverage',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ACTIVE SATELLITES',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              // List active layers
              ..._activeLayers.map((layer) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: layer.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      layer.satellite ?? layer.shortName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      layer.resolution,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )),
            ] else ...[
              Text(
                _primaryLayer.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Resolution', value: _primaryLayer.resolution),
              if (_primaryLayer.satellite != null)
                _InfoRow(label: 'Satellite', value: _primaryLayer.satellite!),
              if (_primaryLayer.dataStartDate != null)
                _InfoRow(
                  label: 'Data Available', 
                  value: 'Since ${GibsService.formatDate(_primaryLayer.dataStartDate!)}',
                ),
              _InfoRow(label: 'Max Zoom', value: 'Level ${_primaryLayer.maxZoom}'),
              _InfoRow(label: 'Category', value: _primaryLayer.category.displayName),
            ],
            const SizedBox(height: 8),
            _InfoRow(label: 'Source', value: 'NASA GIBS WMTS'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Layer picker bottom sheet with checkbox multi-select and presets
class _LayerPickerSheet extends StatefulWidget {
  final List<GibsLayer> initialActiveLayers;
  final GibsLayerPreset? initialActivePreset;
  final Function(List<GibsLayer>, GibsLayerPreset?) onSelectionChanged;

  const _LayerPickerSheet({
    required this.initialActiveLayers,
    required this.initialActivePreset,
    required this.onSelectionChanged,
  });

  @override
  State<_LayerPickerSheet> createState() => _LayerPickerSheetState();
}

class _LayerPickerSheetState extends State<_LayerPickerSheet> {
  late List<GibsLayer> _activeLayers;
  GibsLayerPreset? _activePreset;

  @override
  void initState() {
    super.initState();
    _activeLayers = List.from(widget.initialActiveLayers);
    _activePreset = widget.initialActivePreset;
  }
  
  bool _isLayerActive(GibsLayer layer) {
    return _activeLayers.any((l) => l.id == layer.id);
  }
  
  void _toggleLayer(GibsLayer layer) {
    setState(() {
      final isActive = _isLayerActive(layer);
      if (isActive) {
        // Remove layer (but keep at least one)
        if (_activeLayers.length > 1) {
          _activeLayers.removeWhere((l) => l.id == layer.id);
          _activePreset = null; // Clear preset when manually toggling
        }
      } else {
        // Add layer
        _activeLayers.add(layer);
        _activePreset = null; // Clear preset when manually toggling
      }
    });
    widget.onSelectionChanged(_activeLayers, _activePreset);
  }
  
  void _applyPreset(GibsLayerPreset preset) {
    setState(() {
      _activeLayers = List.from(preset.layers);
      _activePreset = preset;
    });
    widget.onSelectionChanged(_activeLayers, _activePreset);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title with layer count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.satellite_alt, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Satellite Layers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_activeLayers.length} selected',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Presets section
            _buildPresetsSection(),
            const Divider(color: Colors.white12, height: 1),
            // Layer list by category
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var category in GibsLayerCategory.values) ...[
                    _buildCategorySection(category),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPresetsSection() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK PRESETS',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: GibsLayerPreset.allPresets.map((preset) {
                final isActive = _activePreset?.id == preset.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _applyPreset(preset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? preset.color.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive 
                              ? preset.color.withOpacity(0.5)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            preset.icon,
                            color: isActive ? preset.color : Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            preset.name,
                            style: TextStyle(
                              color: isActive ? preset.color : Colors.white70,
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(GibsLayerCategory category) {
    final layers = GibsLayer.byCategory(category);
    if (layers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            category.displayName.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...layers.map((layer) => _buildLayerTile(layer)),
      ],
    );
  }

  Widget _buildLayerTile(GibsLayer layer) {
    final isSelected = _isLayerActive(layer);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleLayer(layer),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? layer.color.withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  layer.icon,
                  color: isSelected ? layer.color : Colors.white54,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            layer.shortName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (layer.satellite != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: layer.color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              layer.satellite!,
                              style: TextStyle(
                                color: layer.color,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      layer.resolution,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Checkbox
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? layer.color : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? layer.color : Colors.white38,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square action button that maintains aspect ratio
class _SquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SquareButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Info row for layer details
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for saved spot in bottom sheet
class _SavedSpotCard extends StatelessWidget {
  final UserSpotResponse spot;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedSpotCard({
    required this.spot,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF6B8E7D).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFF6B8E7D),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${spot.latitude.toStringAsFixed(4)}°, ${spot.longitude.toStringAsFixed(4)}°',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white38),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rifle scope style reticle for pin mode (hunters audience)
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Outer circle (semi-transparent for scope effect)
    final circlePaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 1, circlePaint);
    
    // Crosshair configuration
    final gap = 12.0;
    final lineLength = radius - gap - 4;
    
    // White outline for visibility on any background
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    
    // Black crosshair lines
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    
    // Draw crosshairs (outline first, then black)
    for (final paint in [outlinePaint, linePaint]) {
      // Top
      canvas.drawLine(
        Offset(center.dx, center.dy - gap),
        Offset(center.dx, center.dy - gap - lineLength),
        paint,
      );
      // Bottom
      canvas.drawLine(
        Offset(center.dx, center.dy + gap),
        Offset(center.dx, center.dy + gap + lineLength),
        paint,
      );
      // Left
      canvas.drawLine(
        Offset(center.dx - gap, center.dy),
        Offset(center.dx - gap - lineLength, center.dy),
        paint,
      );
      // Right
      canvas.drawLine(
        Offset(center.dx + gap, center.dy),
        Offset(center.dx + gap + lineLength, center.dy),
        paint,
      );
    }
    
    // Red center dot
    final dotPaint = Paint()..color = Colors.red;
    canvas.drawCircle(center, 3, dotPaint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
