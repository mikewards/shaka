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
import '../../../data/services/ip_geolocation_service.dart';
import '../../../data/services/map_background_service.dart';
import '../../../data/services/map_home_service.dart';
import '../../widgets/search_overlay.dart';
import '../../widgets/background_picker.dart';
import '../../widgets/set_map_home_dialog.dart';

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
  final IpGeolocationService _ipGeoService = IpGeolocationService();
  
  // Default fallback (Hawaii) - used if Map Home and IP geolocation not available
  static const _fallbackCenter = LatLng(21.3069, -157.8583);
  static const _defaultZoom = 8.5; // ~30 mile radius when not using Map Home
  // When using Map Home: ~200 km radius view
  static final _mapHomeZoom = MapHomeService.mapHomeZoom;
  
  // Actual default center (set in initState from Map Home, IP geolocation, or fallback)
  LatLng _defaultCenter = _fallbackCenter;
  double _initialZoom = _defaultZoom;
  
  // NEW: All spots loaded once (for map markers - always visible)
  List<SpotMapMarker> _allSpots = [];
  
  // NEW: Spots filtered to current viewport (for carousel)
  List<SpotMapMarker> _visibleSpots = [];
  
  bool _isLoading = true;
  bool _isMapReady = false;
  String? _error;
  int? _selectedSpotIndex;
  bool _showSearch = false;
  
  // Debounce timer for map animations
  Timer? _mapAnimationDebounce;
  bool _isFromMarkerTap = false;
  
  // Debounce timer for viewport filtering (no API calls, just client-side filter)
  Timer? _viewportFilterDebounce;
  
  // Key to force map rebuild when background changes
  int _mapKey = 0;
  
  // Style version to prevent race conditions during rapid style changes
  int _styleVersion = 0;
  
  // Load version to prevent race conditions between spot loads
  int _loadVersion = 0;
  
  // Store camera position to restore after style change
  CameraPosition? _lastCameraPosition;
  
  // Track pointer for tap detection (to distinguish taps from pans)
  Offset? _pointerDownPosition;
  DateTime? _pointerDownTime;

  @override
  void initState() {
    super.initState();
    _bgService.addListener(_onBackgroundChanged);
    MapHomeService.mapHomeChanged.addListener(_onMapHomeChanged);
    _initDefaultCenter();
    // NOTE: All spots are loaded once in _onStyleLoaded - no location-based reload
  }

  /// When user sets Map Home from Profile, animate to new center.
  void _onMapHomeChanged() {
    if (!mounted) return;
    MapHomeService().getMapHome().then((home) {
      if (home != null && _mapController != null && mounted) {
        _defaultCenter = LatLng(home.lat, home.lon);
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(home.lat, home.lon), _mapHomeZoom),
        );
        debugPrint('ExploreScreen: Moved to Map Home (${home.lat}, ${home.lon})');
      }
    });
  }
  
  Future<void> _initDefaultCenter() async {
    final mapHome = await MapHomeService().getMapHome();
    if (mapHome != null) {
      _defaultCenter = LatLng(mapHome.lat, mapHome.lon);
      _initialZoom = _mapHomeZoom;
      debugPrint('ExploreScreen: Using Map Home (${mapHome.lat}, ${mapHome.lon})');
    } else {
      final ipLocation = _ipGeoService.location;
      if (ipLocation != null) {
        _defaultCenter = LatLng(ipLocation.lat, ipLocation.lon);
        _initialZoom = _defaultZoom;
        debugPrint('ExploreScreen: Using IP location ${ipLocation.city ?? "unknown"}');
      } else {
        _defaultCenter = _fallbackCenter;
        _initialZoom = _defaultZoom;
        debugPrint('ExploreScreen: Using fallback location (Hawaii) - listening for IP');
        _ipGeoService.addListener(_onIpLocationChanged);
      }
    }
    if (mounted) {
      setState(() {});
      // If map was already created with fallback, animate to Map Home
      final home = mapHome;
      if (home != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_mapController != null && mounted) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(home.lat, home.lon),
                _mapHomeZoom,
              ),
            );
          }
        });
      }
    }
    // Show first-launch Map Home prompt if not set (after first frame)
    if (mapHome == null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await SetMapHomeDialog.showIfNeeded(context);
      });
    }
  }
  
  /// Try to animate map to IP location - called from both IP callback and style loaded
  /// Returns true if animation was performed (only when not using Map Home)
  /// NOTE: No longer reloads spots - all spots are loaded once globally
  bool _tryAnimateToIpLocation() {
    final ipLocation = _ipGeoService.location;
    
    // Need: IP available, still at fallback (no Map Home), map ready
    if (ipLocation != null &&
        _defaultCenter == _fallbackCenter &&
        _mapController != null &&
        _isMapReady) {
      debugPrint('ExploreScreen: Animating to IP location - ${ipLocation.city ?? "unknown"}');
      _defaultCenter = LatLng(ipLocation.lat, ipLocation.lon);
      _initialZoom = _defaultZoom;

      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_defaultCenter, _initialZoom),
      );
      // After animation settles, _onCameraIdle will update _visibleSpots

      // Remove listener - we've successfully animated
      _ipGeoService.removeListener(_onIpLocationChanged);
      return true;
    }
    return false;
  }
  
  /// Called when IP geolocation becomes available after initial load
  void _onIpLocationChanged() {
    _tryAnimateToIpLocation();
  }
  
  @override
  void dispose() {
    _mapAnimationDebounce?.cancel();
    _viewportFilterDebounce?.cancel();
    _carouselController.dispose();
    _bgService.removeListener(_onBackgroundChanged);
    MapHomeService.mapHomeChanged.removeListener(_onMapHomeChanged);
    _ipGeoService.removeListener(_onIpLocationChanged);
    _mapController = null;
    super.dispose();
  }
  
  void _onBackgroundChanged() {
    // BLOCK: Don't allow style change while map is loading (prevents iOS crash)
    if (!_isMapReady) {
      debugPrint('Explore: Ignoring style change - map not ready');
      return;
    }
    
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
    // DON'T set _isMapReady here - wait until overlays are loaded
    
    // Try to animate to IP location (just centering, no reload)
    _tryAnimateToIpLocation();
    
    // Load ALL spots once (if not already loaded)
    if (_allSpots.isEmpty) {
      await _loadAllSpots();
    }
    
    // Add overlays first (raster tile layers)
    await _addOverlays();
    
    // CRITICAL: Bail out if style changed during await (prevents iOS crash)
    if (!mounted || _styleVersion != currentVersion) return;
    
    // For styles with overlays, add delay for tiles to start loading
    if (_bgService.hasOverlays(_bgService.current)) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _styleVersion != currentVersion) return;
    }
    
    // NOW set map ready - opaque overlay will hide, revealing loaded map
    if (mounted) setState(() => _isMapReady = true);
    
    // Wait for raster layers to be registered before adding circle annotations
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Bail out if style changed during delay
    if (!mounted || _styleVersion != currentVersion) return;
    
    // Add markers on top - circle annotations should render above raster layers
    await _updateMarkers();
    
    // Update visible spots for carousel
    await _updateVisibleSpots();
    
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
  
  /// Handle map camera changes - filter visible spots for carousel (NO API reload)
  void _onCameraIdle() {
    if (_mapController == null || !_isMapReady) return;
    
    // Debounce viewport filtering for smoother UX
    _viewportFilterDebounce?.cancel();
    _viewportFilterDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _mapController == null) return;
      await _updateVisibleSpots();
    });
  }
  
  /// Filter all spots to those visible in current viewport (client-side, no API)
  Future<void> _updateVisibleSpots() async {
    if (_mapController == null || _allSpots.isEmpty) return;
    
    try {
      // Get current visible bounds
      final bounds = await _mapController!.getVisibleRegion();
      
      // Filter spots to those within bounds
      final visible = _allSpots.where((spot) {
        final lat = spot.coordinates.lat;
        final lon = spot.coordinates.lon;
        return lat >= bounds.southwest.latitude &&
               lat <= bounds.northeast.latitude &&
               lon >= bounds.southwest.longitude &&
               lon <= bounds.northeast.longitude;
      }).toList();
      
      // Sort by score (best first) for carousel
      visible.sort((a, b) => (b.shakaScore ?? 0).compareTo(a.shakaScore ?? 0));
      
      if (mounted) {
        setState(() {
          _visibleSpots = visible;
          // Reset selection when viewport changes
          _selectedSpotIndex = visible.isNotEmpty ? 0 : null;
        });
        
        // Jump carousel to first spot
        if (visible.isNotEmpty && _carouselController.hasClients) {
          _carouselController.jumpToPage(0);
        }
      }
      
      debugPrint('🗺️ Viewport: ${visible.length}/${_allSpots.length} spots visible');
    } catch (e) {
      debugPrint('Error updating visible spots: $e');
    }
  }
  
  /// Load ALL spots once from the server (lightweight data for map markers)
  Future<void> _loadAllSpots({int retryCount = 0, int? version}) async {
    // Increment load version to cancel any in-flight requests
    final currentVersion = version ?? ++_loadVersion;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('🗺️ Loading ALL spots for map (v$currentVersion, attempt ${retryCount + 1})');
      final response = await _apiClient.getAllSpots();
      
      // Only apply results if this is still the current load
      if (mounted && currentVersion == _loadVersion) {
        debugPrint('✅ Loaded ${response.count} spots globally (v$currentVersion)');
        setState(() {
          _allSpots = response.spots;
          _isLoading = false;
        });
        
        if (_isMapReady) {
          await _updateMarkers();
        }
      } else {
        debugPrint('⏭️ Ignoring stale load (v$currentVersion, current is v$_loadVersion)');
      }
    } catch (e) {
      debugPrint('❌ Failed to load all spots (v$currentVersion, attempt ${retryCount + 1}): $e');
      // Retry up to 3 times with exponential backoff, but only if still current
      if (retryCount < 3 && mounted && currentVersion == _loadVersion) {
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        await Future.delayed(delay);
        return _loadAllSpots(retryCount: retryCount + 1, version: currentVersion);
      }
      
      if (mounted && currentVersion == _loadVersion) {
        setState(() {
          _error = 'Could not load spots. Tap to retry.';
          _isLoading = false;
        });
      }
    }
  }
  
  /// Update markers using GeoJSON layer - renders ON TOP of raster overlays
  /// Shows ALL spots (not filtered) - markers persist during pan/zoom
  Future<void> _updateMarkers() async {
    if (_mapController == null || !_isMapReady) {
      return;
    }
    
    final spots = _allSpots;
    
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
    
    // Build GeoJSON features for ALL spots. sortKey = score so when labels overlap,
    // only the highest-score (top) spot's number is shown.
    final features = spots.map((spot) {
      final score = spot.shakaScore ?? 0;
      final color = _getScoreColorHex(score);
      return {
        'type': 'Feature',
        'properties': {
          'id': spot.id,
          'name': spot.name,
          'score': score.toString(),
          'sortKey': score,
          'color': color,
          'radius': 14,
          'strokeWidth': 2,
          'strokeColor': '#FFFFFF',
          'textSize': 11,
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
      
      // Score labels only when zoomed in (minzoom 12) so overlapping bubbles don't show scores.
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
          textAllowOverlap: false,
          textIgnorePlacement: false,
          symbolSortKey: ['get', 'sortKey'],
        ),
        minzoom: 12,
      );
      
      debugPrint('🗺️ Rendered ${spots.length} spot markers');
    } catch (e) {
      debugPrint('Failed to add spots layer: $e');
    }
  }
  
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
    
    // Animate to selected spot (no markers rebuild needed)
    _mapAnimationDebounce?.cancel();
    _mapAnimationDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _mapController == null) return;
      if (index < _visibleSpots.length) {
        final spot = _visibleSpots[index];
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(spot.coordinates.lat, spot.coordinates.lon),
            10.0,
          ),
        );
      }
    });
  }
  
  /// Handle map taps - find tapped spot and select it in carousel
  Future<void> _handleMapTap(Offset screenPoint) async {
    if (_mapController == null || !_isMapReady) return;
    
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    
    // Try BOTH coordinate interpretations to find which one works
    final tapLogical = screenPoint;
    final tapPhysical = screenPoint * devicePixelRatio;
    
    if (_allSpots.isEmpty) return;
    
    // Find closest spot from ALL spots (markers are always visible)
    SpotMapMarker? closestSpot;
    double closestDist = double.infinity;
    
    for (final spot in _allSpots) {
      // Bail out if controller was nulled (style change)
      if (_mapController == null) return;
      
      final spotLatLng = LatLng(spot.coordinates.lat, spot.coordinates.lon);
      final spotScreenPos = await _mapController!.toScreenLocation(spotLatLng);
      
      // Check again after await
      if (_mapController == null) return;
      
      // Try both coordinate systems and use the closer match
      final dxL = tapLogical.dx - spotScreenPos.x;
      final dyL = tapLogical.dy - spotScreenPos.y;
      final distLogical = sqrt(dxL * dxL + dyL * dyL);
      
      final dxP = tapPhysical.dx - spotScreenPos.x;
      final dyP = tapPhysical.dy - spotScreenPos.y;
      final distPhysical = sqrt(dxP * dxP + dyP * dyP);
      
      final minDist = distLogical < distPhysical ? distLogical : distPhysical;
      
      if (minDist < closestDist) {
        closestDist = minDist;
        closestSpot = spot;
      }
    }
    
    // Use generous threshold to find match
    const threshold = 50.0;
    
    if (closestDist < threshold && closestSpot != null) {
      debugPrint('Marker tap: ${closestSpot.name} (dist ${closestDist.toStringAsFixed(0)}px)');
      _onMarkerTapped(closestSpot);
    }
  }
  
  /// Handle marker tap - navigate to spot (may need to zoom if out of viewport)
  void _onMarkerTapped(SpotMapMarker tappedSpot) {
    HapticFeedback.selectionClick();
    
    // Find spot in visible carousel (if present)
    final visibleIndex = _visibleSpots.indexWhere((s) => s.id == tappedSpot.id);
    
    if (visibleIndex >= 0) {
      // Spot is in carousel - just select it
      _isFromMarkerTap = true;
      setState(() => _selectedSpotIndex = visibleIndex);
      
      _carouselController.animateToPage(
        visibleIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Spot is not in current viewport - animate to it
      // After animation, _onCameraIdle will update _visibleSpots and it will appear
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(tappedSpot.coordinates.lat, tappedSpot.coordinates.lon),
          10.0,
        ),
      );
    }
  }

  /// Open spot detail page - works with either SpotMapMarker or SpotSummary
  void _openSpotDetail(SpotMapMarker spot) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {
      'date': today,
      // Don't pass spot summary - let detail page fetch it fresh
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
                        initialCameraPosition: _lastCameraPosition ?? CameraPosition(
                          target: _defaultCenter,
                          zoom: _initialZoom,
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
                    
                    // Loading overlay - opaque dark background hides map until ready
                    if (_isLoading || !_isMapReady)
                      Positioned.fill(
                        child: Container(
                          color: const Color(0xFF0D0D0D),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.info,
                            ),
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
                                    onPressed: _loadAllSpots,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _visibleSpots.isEmpty
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
    // No API reload needed - all spots already loaded, _onCameraIdle will filter
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(region.centerLat, region.centerLon),
        6.0,
      ),
    );
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Text(
                '${_visibleSpots.length} spots in view',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${_allSpots.length} total',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: PageView.builder(
            controller: _carouselController,
            itemCount: _visibleSpots.length,
            onPageChanged: _onSpotSelected,
            itemBuilder: (context, index) {
              final spot = _visibleSpots[index];
              final isSelected = index == _selectedSpotIndex;
              
              return AnimatedScale(
                scale: isSelected ? 1.0 : 0.95,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: () => _openSpotDetail(spot),
                  child: _SpotMarkerCard(spot: spot),
                ),
              );
            },
          ),
        ),
        
        // Carousel dots with proper padding
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _visibleSpots.length.clamp(0, 10),
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _selectedSpotIndex ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _selectedSpotIndex
                      ? AppColors.info
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

/// Lightweight spot card for carousel (uses SpotMapMarker, no conditions)
/// Tap to open full detail page where conditions are shown
class _SpotMarkerCard extends StatelessWidget {
  final SpotMapMarker spot;

  const _SpotMarkerCard({required this.spot});

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);

  String _getScoreLabel(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    final score = spot.shakaScore ?? 0;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Score badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getScoreColor(score).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getScoreColor(score),
                width: 2,
              ),
            ),
            child: Center(
              child: spot.shakaScore != null
                  ? Text(
                      '$score',
                      style: TextStyle(
                        color: _getScoreColor(score),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Icon(
                      Icons.hourglass_empty,
                      color: _getScoreColor(score),
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Spot info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getScoreColor(score).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        spot.shakaScore != null ? _getScoreLabel(score) : 'Loading...',
                        style: TextStyle(
                          color: _getScoreColor(score),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        spot.region,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Condition row (swell + wind) with bordered chips
                if (spot.swell != null || spot.wind != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        if (spot.swell != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.waves, size: 11, color: Colors.white54),
                                const SizedBox(width: 4),
                                Text(
                                  spot.swell!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (spot.wind != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.air, size: 11, color: Colors.white54),
                                const SizedBox(width: 4),
                                Text(
                                  spot.wind!,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          // Chevron hint
          const Icon(Icons.chevron_right, color: Colors.white38, size: 24),
        ],
      ),
    );
  }
}
