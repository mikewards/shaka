import 'dart:async';
import 'dart:math' show Point, sqrt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../../data/services/map_background_service.dart';
import '../../widgets/search_overlay.dart';
import '../../widgets/background_picker.dart';

/// Full-screen explore map for discovering dive spots.
/// Surfline-style: Map 70% top, horizontal spot carousel 30% bottom.
/// Now using MapLibre for consistent map experience across the app.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  MaplibreMapController? _mapController;
  final ShakaApiClient _apiClient = ShakaApiClient();
  final PageController _carouselController = PageController(viewportFraction: 0.85);
  final MapBackgroundService _bgService = MapBackgroundService();
  
  // Default to Hawaii
  static const _defaultCenter = LatLng(21.3069, -157.8583);
  static const _defaultZoom = 7.5;
  
  List<SpotSummary> _spots = [];
  bool _isLoading = true;
  bool _isMapReady = false;
  String? _error;
  int? _selectedSpotIndex = 0;
  bool _showSearch = false;
  
  // Debounce timer for map animations
  Timer? _mapAnimationDebounce;
  bool _isFromMarkerTap = false;
  
  // Track last search center to detect significant map movement
  LatLng _lastSearchCenter = _defaultCenter;
  Timer? _mapMoveDebounce;
  
  // Key to force map rebuild when background changes
  int _mapKey = 0;
  
  // Style version to prevent race conditions during rapid style changes
  int _styleVersion = 0;
  
  // Store camera position to restore after style change
  CameraPosition? _lastCameraPosition;
  
  // Track pointer for tap detection (to distinguish taps from pans)
  Offset? _pointerDownPosition;
  DateTime? _pointerDownTime;

  @override
  void initState() {
    super.initState();
    _bgService.addListener(_onBackgroundChanged);
    _loadSpots();
  }
  
  @override
  void dispose() {
    _mapAnimationDebounce?.cancel();
    _mapMoveDebounce?.cancel();
    _carouselController.dispose();
    _bgService.removeListener(_onBackgroundChanged);
    _mapController = null;
    super.dispose();
  }
  
  void _onBackgroundChanged() {
    // Save current camera position before rebuilding map
    if (_mapController != null) {
      _lastCameraPosition = _mapController!.cameraPosition;
    }
    
    // Clear map controller (map will be rebuilt)
    _mapController = null;
    _isMapReady = false;
    
    // Increment style version to cancel any in-progress async operations
    _styleVersion++;
    
    // Increment key to force MapLibreMap widget rebuild with new style
    // Also clear any error state so it doesn't persist
    setState(() {
      _mapKey++;
      _error = null;
    });
  }
  
  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
  }
  
  void _onStyleLoaded() async {
    // Capture current style version to detect if user changed styles during async ops
    final currentVersion = _styleVersion;
    
    debugPrint('_onStyleLoaded: Style loaded for ${_bgService.current}');
    if (mounted) setState(() => _isMapReady = true);
    
    // Add overlays first (raster tile layers)
    await _addOverlays();
    
    // CRITICAL: Bail out if style changed during await (prevents iOS crash)
    if (!mounted || _styleVersion != currentVersion) return;
    
    // Wait for raster layers to be registered before adding circle annotations
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Bail out if style changed during delay
    if (!mounted || _styleVersion != currentVersion) return;
    
    // Add markers on top - circle annotations should render above raster layers
    await _updateMarkers();
    
    debugPrint('_onStyleLoaded: Complete for ${_bgService.current}');
  }
  
  /// Add raster overlays based on current background
  Future<void> _addOverlays() async {
    if (_mapController == null) return;
    
    final overlays = _bgService.getOverlays(_bgService.current);
    debugPrint('Adding ${overlays.length} overlays for ${_bgService.current}');
    
    for (final overlay in overlays) {
      // Bail out if controller was nulled (style change in progress)
      if (_mapController == null) return;
      
      try {
        // Remove existing source/layer if present (use safe ?. operator)
        try {
          await _mapController?.removeLayer('${overlay.id}-layer');
          await _mapController?.removeSource(overlay.id);
        } catch (_) {}
        
        // Check again after awaits
        if (_mapController == null) return;
        
        debugPrint('Adding overlay: ${overlay.id} from ${overlay.urlTemplate}');
        
        // Add raster source
        await _mapController!.addSource(
          overlay.id,
          RasterSourceProperties(
            tiles: [overlay.urlTemplate],
            tileSize: overlay.tileSize.toDouble(),
            minzoom: overlay.minZoom,
            maxzoom: overlay.maxZoom,
          ),
        );
        
        // Check after await
        if (_mapController == null) return;
        
        // Add raster layer
        await _mapController!.addRasterLayer(
          overlay.id,
          '${overlay.id}-layer',
          RasterLayerProperties(
            rasterOpacity: overlay.opacity,
          ),
        );
        
        debugPrint('Successfully added overlay: ${overlay.id}');
      } catch (e) {
        debugPrint('Failed to add overlay ${overlay.id}: $e');
      }
    }
  }
  
  /// Handle map camera changes - reload spots only if panned significantly
  void _onCameraIdle() {
    if (_mapController == null || !_isMapReady) return;
    
    // NOTE: We do NOT update markers here - the GeoJSON layer auto-renders at correct positions
    // We only reload spots if the user panned significantly to a new area
    
    _mapMoveDebounce?.cancel();
    _mapMoveDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted || _mapController == null) return;
      
      final camera = _mapController!.cameraPosition;
      if (camera == null) return;
      
      final newCenter = camera.target;
      
      // Calculate distance from last search (rough km estimate)
      final latDiff = (newCenter.latitude - _lastSearchCenter.latitude).abs();
      final lonDiff = (newCenter.longitude - _lastSearchCenter.longitude).abs();
      final roughDistanceKm = (latDiff + lonDiff) * 111;
      
      // Only re-search if panned significantly (>100km) - increased threshold
      if (roughDistanceKm > 100) {
        _lastSearchCenter = newCenter;
        _loadSpotsForLocation(newCenter.latitude, newCenter.longitude);
      }
    });
  }
  
  /// Load spots for a specific location with retry
  Future<void> _loadSpotsForLocation(double lat, double lon, {int retryCount = 0}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      debugPrint('🌊 Loading spots for: $lat, $lon (attempt ${retryCount + 1})');
      final response = await _apiClient.searchSpots(
        lat: lat,
        lon: lon,
        date: today,
        radiusKm: 160,
      );
      
      if (mounted) {
        debugPrint('✅ Loaded ${response.spots.length} spots');
        setState(() {
          _spots = response.spots;
          _isLoading = false;
          _selectedSpotIndex = _spots.isNotEmpty ? 0 : null;
        });
        
        // Only jump to page if controller is attached
        if (_spots.isNotEmpty && _carouselController.hasClients) {
          _carouselController.jumpToPage(0);
        }
        
        await _updateMarkers();
      }
    } catch (e) {
      debugPrint('❌ Error loading spots (attempt ${retryCount + 1}): $e');
      // Retry up to 3 times with exponential backoff
      if (retryCount < 3 && mounted) {
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        await Future.delayed(delay);
        return _loadSpotsForLocation(lat, lon, retryCount: retryCount + 1);
      }
      
      if (mounted) {
        setState(() {
          _error = 'Could not load spots. Tap to retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSpots({int retryCount = 0}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      debugPrint('🌊 Initial load (attempt ${retryCount + 1})');
      final response = await _apiClient.searchSpots(
        lat: _defaultCenter.latitude,
        lon: _defaultCenter.longitude,
        date: today,
        radiusKm: 160,
      );
      
      if (mounted) {
        debugPrint('✅ Initial load: ${response.spots.length} spots');
        setState(() {
          _spots = response.spots;
          _isLoading = false;
        });
        
        if (_isMapReady) {
          await _updateMarkers();
        }
      }
    } catch (e) {
      debugPrint('❌ Initial load failed (attempt ${retryCount + 1}): $e');
      // Retry up to 3 times with exponential backoff
      if (retryCount < 3 && mounted) {
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        await Future.delayed(delay);
        return _loadSpots(retryCount: retryCount + 1);
      }
      
      if (mounted) {
        setState(() {
          _error = 'Could not load spots. Tap to retry.';
          _isLoading = false;
        });
      }
    }
  }
  
  /// Update markers using GeoJSON layer - renders ON TOP of raster overlays
  /// This replaces the annotation approach which got buried under raster layers
  Future<void> _updateMarkers() async {
    if (_mapController == null || !_isMapReady) {
      return;
    }
    
    final spots = _filteredSpots;
    
    // Remove existing marker layers and source (use safe ?. operator)
    try {
      await _mapController?.removeLayer('spots-labels');
    } catch (_) {}
    try {
      await _mapController?.removeLayer('spots-layer');
    } catch (_) {}
    try {
      await _mapController?.removeSource('spots-source');
    } catch (_) {}
    
    // Bail out if controller was nulled during removals
    if (_mapController == null) return;
    
    if (spots.isEmpty) {
      return;
    }
    
    // Build GeoJSON features for all spots
    // Selected markers are MUCH larger with cyan accent stroke for clear visibility
    final features = spots.asMap().entries.map((entry) {
      final i = entry.key;
      final spot = entry.value;
      final isSelected = i == _selectedSpotIndex;
      final color = _getScoreColorHex(spot.shakaScore);
      
      return {
        'type': 'Feature',
        'properties': {
          'index': i,
          'name': spot.name,
          'score': spot.shakaScore.toString(),
          'color': color,
          // Selected: 2x larger with thick cyan stroke
          'radius': isSelected ? 24 : 14,
          'strokeWidth': isSelected ? 5 : 2,
          'strokeColor': isSelected ? '#00BCD4' : '#FFFFFF',
          'textSize': isSelected ? 13 : 11,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [spot.coordinates.lon, spot.coordinates.lat],
        },
      };
    }).toList();
    
    final geojson = {
      'type': 'FeatureCollection',
      'features': features,
    };
    
    // Bail out if controller was nulled during feature building
    if (_mapController == null) return;
    
    try {
      // Add GeoJSON source
      await _mapController!.addSource(
        'spots-source',
        GeojsonSourceProperties(data: geojson),
      );
      
      // Check after await
      if (_mapController == null) return;
      
      // Add circle layer - base circles with score colors
      await _mapController!.addCircleLayer(
        'spots-source',
        'spots-layer',
        const CircleLayerProperties(
          circleRadius: ['get', 'radius'],
          circleColor: ['get', 'color'],
          circleStrokeColor: ['get', 'strokeColor'],
          circleStrokeWidth: ['get', 'strokeWidth'],
          circleOpacity: 1.0,
          circleStrokeOpacity: 1.0,
        ),
      );
      
      // Check after await
      if (_mapController == null) return;
      
      // Add symbol layer for score text on top of circles
      await _mapController!.addSymbolLayer(
        'spots-source',
        'spots-labels',
        const SymbolLayerProperties(
          textField: ['get', 'score'],
          textSize: ['get', 'textSize'],
          textColor: '#FFFFFF',
          textFont: ['Open Sans Bold', 'Arial Unicode MS Bold'],
          textHaloColor: '#000000',
          textHaloWidth: 1.0,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
      );
    } catch (e) {
      debugPrint('Failed to add spots layer: $e');
    }
  }

  List<SpotSummary> get _filteredSpots => _spots;

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);
  
  String _getScoreColorHex(int score) {
    final color = AppColors.getScoreColor(score);
    return '#${color.value.toRadixString(16).substring(2)}';
  }

  void _onSpotSelected(int index) {
    if (index == _selectedSpotIndex) return;
    
    // Check marker tap flag BEFORE haptic to avoid double-buzz
    if (_isFromMarkerTap) {
      _isFromMarkerTap = false;
      setState(() => _selectedSpotIndex = index);
      return;
    }
    
    HapticFeedback.selectionClick();
    setState(() => _selectedSpotIndex = index);
    
    _mapAnimationDebounce?.cancel();
    _mapAnimationDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _mapController == null) return;
      final spots = _filteredSpots;
      if (index < spots.length) {
        final spot = spots[index];
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(spot.coordinates.lat, spot.coordinates.lon),
            10.0,
          ),
        );
        _updateMarkers();
      }
    });
  }
  
  /// Handle map taps - test both with and without devicePixelRatio scaling
  Future<void> _handleMapTap(Offset screenPoint) async {
    if (_mapController == null || !_isMapReady) return;
    
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    
    // Try BOTH coordinate interpretations to find which one works
    final tapLogical = screenPoint;
    final tapPhysical = screenPoint * devicePixelRatio;
    
    debugPrint('');
    debugPrint('=== TAP DIAGNOSTIC ===');
    debugPrint('Device pixel ratio: $devicePixelRatio');
    debugPrint('Tap LOGICAL (raw): (${tapLogical.dx.toStringAsFixed(1)}, ${tapLogical.dy.toStringAsFixed(1)})');
    debugPrint('Tap PHYSICAL (*dpr): (${tapPhysical.dx.toStringAsFixed(1)}, ${tapPhysical.dy.toStringAsFixed(1)})');
    
    final spots = _filteredSpots;
    if (spots.isEmpty) return;
    
    // Find closest spot using BOTH coordinate systems
    int? closestLogicalIndex;
    double closestLogicalDist = double.infinity;
    int? closestPhysicalIndex;
    double closestPhysicalDist = double.infinity;
    
    for (int i = 0; i < spots.length; i++) {
      // Bail out if controller was nulled (style change)
      if (_mapController == null) return;
      
      final spot = spots[i];
      final spotLatLng = LatLng(spot.coordinates.lat, spot.coordinates.lon);
      final spotScreenPos = await _mapController!.toScreenLocation(spotLatLng);
      
      // Check again after await
      if (_mapController == null) return;
      
      // Distance using logical tap
      final dxL = tapLogical.dx - spotScreenPos.x;
      final dyL = tapLogical.dy - spotScreenPos.y;
      final distLogical = sqrt(dxL * dxL + dyL * dyL);
      
      // Distance using physical tap
      final dxP = tapPhysical.dx - spotScreenPos.x;
      final dyP = tapPhysical.dy - spotScreenPos.y;
      final distPhysical = sqrt(dxP * dxP + dyP * dyP);
      
      if (i < 3) {
        debugPrint('Spot $i: mapPos=(${spotScreenPos.x.toStringAsFixed(0)}, ${spotScreenPos.y.toStringAsFixed(0)}) distL=${distLogical.toStringAsFixed(0)} distP=${distPhysical.toStringAsFixed(0)}');
      }
      
      if (distLogical < closestLogicalDist) {
        closestLogicalDist = distLogical;
        closestLogicalIndex = i;
      }
      if (distPhysical < closestPhysicalDist) {
        closestPhysicalDist = distPhysical;
        closestPhysicalIndex = i;
      }
    }
    
    debugPrint('--- RESULTS ---');
    debugPrint('LOGICAL closest: spot $closestLogicalIndex at ${closestLogicalDist.toStringAsFixed(1)}px');
    debugPrint('PHYSICAL closest: spot $closestPhysicalIndex at ${closestPhysicalDist.toStringAsFixed(1)}px');
    
    // Use whichever coordinate system gives a match within threshold
    const threshold = 50.0; // Generous threshold to find ANY match
    
    if (closestPhysicalDist < threshold && closestPhysicalIndex != null) {
      debugPrint('SELECTING via PHYSICAL coordinates');
      _onMarkerTapped(closestPhysicalIndex);
    } else if (closestLogicalDist < threshold && closestLogicalIndex != null) {
      debugPrint('SELECTING via LOGICAL coordinates');
      _onMarkerTapped(closestLogicalIndex);
    } else {
      debugPrint('NO MATCH within ${threshold}px threshold');
    }
    debugPrint('=== END ===');
  }
  
  void _onMarkerTapped(int index) {
    if (index == _selectedSpotIndex) return;
    
    _isFromMarkerTap = true;
    HapticFeedback.selectionClick();
    setState(() => _selectedSpotIndex = index);
    
    final spot = _filteredSpots[index];
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(spot.coordinates.lat, spot.coordinates.lon),
        10.0,
      ),
    );
    
    _carouselController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    _updateMarkers();
  }

  void _openSpotDetail(SpotSummary spot) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {
      'date': today,
      'spot': spot,
    });
  }
  
  void _showBackgroundPicker() {
    showBackgroundPicker(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    final mapHeight = screenHeight * 0.70;  // Increased from 0.65

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          Column(
            children: [
              // Map section (65%)
              SizedBox(
                height: mapHeight,
                child: Stack(
                  children: [
                    // MapLibre Map with Listener for tap detection
                    // Using Listener at pointer level to detect taps without blocking map gestures
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        _pointerDownPosition = event.localPosition;
                        _pointerDownTime = DateTime.now();
                      },
                      onPointerUp: (event) {
                        // Only handle quick taps (not pan gestures)
                        final downPos = _pointerDownPosition;
                        final downTime = _pointerDownTime;
                        _pointerDownPosition = null;
                        _pointerDownTime = null;
                        
                        if (downPos == null || downTime == null) return;
                        
                        // Check if it was a tap (short duration, small movement)
                        final duration = DateTime.now().difference(downTime);
                        final distance = (event.localPosition - downPos).distance;
                        
                        if (duration.inMilliseconds < 300 && distance < 20) {
                          debugPrint('TAP DETECTED at ${event.localPosition}');
                          _handleMapTap(event.localPosition);
                        }
                      },
                      child: MaplibreMap(
                        key: ValueKey('map_$_mapKey'),
                        onMapCreated: _onMapCreated,
                        onStyleLoadedCallback: _onStyleLoaded,
                        onCameraIdle: _onCameraIdle,
                        initialCameraPosition: _lastCameraPosition ?? const CameraPosition(
                          target: _defaultCenter,
                          zoom: _defaultZoom,
                        ),
                        styleString: _bgService.getStyleUrl(_bgService.current),
                        minMaxZoomPreference: const MinMaxZoomPreference(3, 18),
                        trackCameraPosition: true,
                        compassEnabled: false,
                        attributionButtonMargins: const Point(-100, -100),
                        logoViewMargins: const Point(-100, -100),
                      ),
                    ),
                    
                    // Search bar overlay
                    Positioned(
                      top: topPadding + 12,
                      left: 16,
                      right: 16,
                      child: _buildSearchBar(),
                    ),
                    
                    // Background picker button (left-aligned)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: _buildBackgroundButton(),
                    ),
                    
                    // Loading indicator
                    if (_isLoading || !_isMapReady)
                      const Positioned.fill(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF5B9BD5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Carousel section (35%)
              Expanded(
                child: Container(
                  color: const Color(0xFF0D0D0D),
                  child: _isLoading
                      ? const Center(
                          child: Text(
                            'Loading spots...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.white38, size: 32),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Failed to load spots',
                                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _loadSpots,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _filteredSpots.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No spots found',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : _buildSpotCarousel(),
                ),
              ),
            ],
          ),

          // Search overlay
          if (_showSearch)
            SearchOverlay(
              onSpotSelected: (spot) {
                setState(() => _showSearch = false);
                _navigateToSpot(spot);
              },
              onRegionSelected: (region) {
                setState(() => _showSearch = false);
                _navigateToRegion(region);
              },
              onClose: () => setState(() => _showSearch = false),
            ),
        ],
      ),
    );
  }

  void _navigateToSpot(SpotSearchResult spot) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {'date': today});
  }

  void _navigateToRegion(RegionInfo region) {
    // Zoom out more for regions to show all spots (zoom 6 for large regions)
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(region.centerLat, region.centerLon),
        6.0,
      ),
    );
    _loadSpotsForRegion(region);
  }

  Future<void> _loadSpotsForRegion(RegionInfo region) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Use larger radius (500km) for regions - some like Tahiti/French Polynesia span many islands
      final response = await _apiClient.searchSpots(
        lat: region.centerLat,
        lon: region.centerLon,
        date: today,
        radiusKm: 500,
      );
      
      if (mounted) {
        setState(() {
          _spots = response.spots;
          _isLoading = false;
          _selectedSpotIndex = 0;
        });
        if (_spots.isNotEmpty) {
          _carouselController.jumpToPage(0);
        }
        await _updateMarkers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _showSearch = true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            Text(
              'Search spots...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundButton() {
    return GestureDetector(
      onTap: _showBackgroundPicker,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(
          Icons.layers,
          color: Colors.white70,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildSpotCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),  // Reduced padding
          child: Row(
            children: [
              Text(
                '${_filteredSpots.length} spots nearby',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'Today\'s conditions',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: PageView.builder(
            controller: _carouselController,
            itemCount: _filteredSpots.length,
            onPageChanged: _onSpotSelected,
            itemBuilder: (context, index) {
              final spot = _filteredSpots[index];
              final isSelected = index == _selectedSpotIndex;
              
              return AnimatedScale(
                scale: isSelected ? 1.0 : 0.95,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: () => _openSpotDetail(spot),
                  child: _SpotCard(spot: spot),
                ),
              );
            },
          ),
        ),
        
        // Carousel dots with proper padding
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _filteredSpots.length.clamp(0, 10),
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _selectedSpotIndex ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _selectedSpotIndex
                      ? const Color(0xFF5B9BD5)
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual spot card in the carousel
class _SpotCard extends StatelessWidget {
  final SpotSummary spot;

  const _SpotCard({required this.spot});

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);

  String _getScoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _getScoreColor(spot.shakaScore).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _getScoreColor(spot.shakaScore),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${spot.shakaScore}',
                    style: TextStyle(
                      color: _getScoreColor(spot.shakaScore),
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getScoreColor(spot.shakaScore).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getScoreLabel(spot.shakaScore),
                        style: TextStyle(
                          color: _getScoreColor(spot.shakaScore),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              _ConditionChip(
                icon: Icons.visibility,
                value: spot.conditions.visibility.split(' ').first,
              ),
              const SizedBox(width: 6),
              _ConditionChip(
                icon: Icons.thermostat,
                value: spot.conditions.waterTemp.split(' ').first,
              ),
              const SizedBox(width: 6),
              _ConditionChip(
                icon: Icons.waves,
                value: spot.conditions.swell.split('@').first.trim(),
              ),
              const SizedBox(width: 6),
              _ConditionChip(
                icon: Icons.air,
                value: spot.conditions.wind,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ConditionChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 18),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
