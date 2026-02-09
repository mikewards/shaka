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
import '../../widgets/background_picker.dart';
import '../../widgets/set_map_home_dialog.dart';
import '../../widgets/save_spot_sheet.dart';

/// Full-screen explore map for discovering dive spots.
/// Surfline-style: Map 70% top, horizontal spot carousel 30% bottom.
/// Now using MapLibre for consistent map experience across the app.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  /// Notifies MainShell to hide/show bottom nav during pin mode.
  static final pinModeActive = ValueNotifier<bool>(false);

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

  /// When false, we have not yet resolved initial center (getMapHome); map is not built so we avoid cold-start animateCamera crash.
  bool _initialCenterReady = false;

  // Combined spots: curated + user saved spots (rebuilt when either changes)
  List<SpotMapMarker> _allSpots = [];
  
  // NEW: Spots filtered to current viewport (for carousel)
  List<SpotMapMarker> _visibleSpots = [];
  
  bool _isLoading = true;
  bool _isMapReady = false;
  /// True only after spots are loaded, markers added, and carousel updated; used for loading overlay only.
  bool _mapFullyReady = false;
  String? _error;
  int? _selectedSpotIndex;
  
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
  
  // Saved spots state
  List<SpotMapMarker> _curatedSpots = [];  // From /spots/all
  List<UserSpotResponse> _userSpots = [];  // From /user-spots
  bool _showSpotsOnMap = true;  // Toggle user spots visibility
  
  // Pin mode state
  bool _isPinMode = false;
  LatLng? _currentCenter;
  
  // Pulse animation for loading user spots (no score yet)
  Timer? _spotPulseTimer;
  bool _pulseExpanded = false;

  @override
  void initState() {
    super.initState();
    _bgService.addListener(_onBackgroundChanged);
    MapHomeService.mapHomeChanged.addListener(_onMapHomeChanged);
    _initDefaultCenter();
    // NOTE: All spots are loaded once in _onStyleLoaded - no location-based reload
    _loadSavedSpots();
  }

  /// When user sets Map Home from Profile, animate to new center (map is already up and ready).
  void _onMapHomeChanged() {
    if (!mounted) return;
    MapHomeService().getMapHome().then((home) {
      if (home != null && _mapController != null && mounted && _isMapReady) {
        _defaultCenter = LatLng(home.lat, home.lon);
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(home.lat, home.lon), _mapHomeZoom),
        );
        debugPrint('ExploreScreen: Moved to Map Home (${home.lat}, ${home.lon})');
      }
    });
  }

  /// Resolve initial center (Map Home, IP, or fallback) then set _initialCenterReady so the map is built once with correct initialCameraPosition (avoids cold-start animateCamera crash).
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
      setState(() => _initialCenterReady = true);
    }
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
    _spotPulseTimer?.cancel();
    _carouselController.dispose();
    _bgService.removeListener(_onBackgroundChanged);
    MapHomeService.mapHomeChanged.removeListener(_onMapHomeChanged);
    _ipGeoService.removeListener(_onIpLocationChanged);
    ExploreScreen.pinModeActive.value = false;
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
    _mapFullyReady = false;
    
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
    
    // Load curated spots once (if not already loaded)
    if (_curatedSpots.isEmpty) {
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
    
    // Loading overlay hides only after spots + markers + carousel are ready
    if (mounted) setState(() => _mapFullyReady = true);
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
        // Preserve current selection if the spot is still in the new viewport
        String? selectedId;
        if (_selectedSpotIndex != null && _selectedSpotIndex! < _visibleSpots.length) {
          selectedId = _visibleSpots[_selectedSpotIndex!].id;
        }

        int newIndex = 0;
        if (selectedId != null && visible.isNotEmpty) {
          final idx = visible.indexWhere((s) => s.id == selectedId);
          if (idx >= 0) newIndex = idx;
        }

        setState(() {
          _visibleSpots = visible;
          _selectedSpotIndex = visible.isNotEmpty ? newIndex : null;
        });

        // Sync carousel to match selection (no-op if already there)
        if (visible.isNotEmpty && _carouselController.hasClients) {
          final currentPage = _carouselController.page?.round() ?? -1;
          if (currentPage != newIndex) {
            _carouselController.jumpToPage(newIndex);
          }
        }

        // Highlight selected spot on map
        _updateSelectedMarker();
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
          _curatedSpots = response.spots;
          _rebuildCombinedSpots();
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
  
  // ===========================================
  // SAVED SPOTS + PIN MODE
  // ===========================================

  /// Rebuild the combined spots list (curated + user saved spots)
  void _rebuildCombinedSpots() {
    _allSpots = [
      ..._curatedSpots,
      if (_showSpotsOnMap) ..._userSpots.map((s) => s.toSpotMapMarker()),
    ];
  }

  /// Load user's saved spots from API
  Future<void> _loadSavedSpots() async {
    debugPrint('📍 Explore: Loading saved spots...');
    try {
      final response = await _apiClient.getUserSpots();
      debugPrint('📍 Explore: Got ${response.spots.length} user spots');
      if (mounted) {
        setState(() {
          _userSpots = response.spots;
          _rebuildCombinedSpots();
        });
        // Update markers if map is ready
        if (_isMapReady) {
          await _updateMarkers();
          await _updateVisibleSpots();
        }
        // Fetch scores for spots that don't have them
        _fetchMissingScores();
      }
    } catch (e) {
      debugPrint('📍 Explore: FAILED to load saved spots: $e');
    }
  }

  /// Fetch shaka scores for user spots that don't have them
  Future<void> _fetchMissingScores() async {
    final spotsNeedingScores = _userSpots.where((s) => s.shakaScore == null).toList();
    if (spotsNeedingScores.isEmpty) {
      debugPrint('📍 Explore: All user spots have scores');
      _stopPulseTimer();
      return;
    }

    // Start pulse animation for loading spots
    if (_showSpotsOnMap) _startPulseTimer();

    debugPrint('📍 Explore: Fetching scores for ${spotsNeedingScores.length} spots...');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    bool anyUpdated = false;

    final futures = <Future>[];
    for (final spot in spotsNeedingScores) {
      futures.add(_fetchSpotScore(spot.id, today).then((score) {
        if (score != null) {
          final index = _userSpots.indexWhere((s) => s.id == spot.id);
          if (index != -1) {
            _userSpots[index] = UserSpotResponse(
              id: spot.id,
              name: spot.name,
              coordinates: spot.coordinates,
              region: spot.region,
              country: spot.country,
              createdAt: spot.createdAt,
              isUserSpot: spot.isUserSpot,
              shakaScore: score,
              swell: spot.swell,
              wind: spot.wind,
              waterTemp: spot.waterTemp,
            );
            anyUpdated = true;
          }
        }
      }));
    }

    await Future.wait(futures);

    if (anyUpdated && mounted && _showSpotsOnMap) {
      debugPrint('📍 Explore: Updated spot scores, refreshing markers');
      setState(() => _rebuildCombinedSpots());
      await _updateMarkers();
      await _updateVisibleSpots();
    }

    if (_userSpots.every((s) => s.shakaScore != null)) {
      _stopPulseTimer();
    }
  }

  Future<int?> _fetchSpotScore(String spotId, String date) async {
    try {
      final detail = await _apiClient.getUserSpotDetail(spotId: spotId, date: date);
      return detail.spot.score.overall;
    } catch (e) {
      debugPrint('📍 Explore: Failed to fetch score for $spotId: $e');
      return null;
    }
  }

  // Pulse timer for loading user spots
  void _startPulseTimer() {
    if (_spotPulseTimer != null) return;
    _pulseExpanded = false;
    _spotPulseTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pulseExpanded = !_pulseExpanded;
      _updatePulseRing();
    });
    _updatePulseRing();
  }

  void _stopPulseTimer() {
    _spotPulseTimer?.cancel();
    _spotPulseTimer = null;
    _removePulseRing();
  }

  Future<void> _removePulseRing() async {
    try { await _mapController?.removeLayer('user-spots-pulse-layer'); } catch (_) {}
    try { await _mapController?.removeSource('user-spots-pulse-source'); } catch (_) {}
  }

  Future<void> _updatePulseRing() async {
    if (_mapController == null) return;

    final loadingSpots = _userSpots.where((s) => s.shakaScore == null).toList();
    if (loadingSpots.isEmpty) {
      _stopPulseTimer();
      return;
    }

    await _removePulseRing();
    if (_mapController == null) return;

    final radius = _pulseExpanded ? 24.0 : 16.0;
    final opacity = _pulseExpanded ? 0.15 : 0.35;

    final features = loadingSpots.map((spot) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [spot.longitude, spot.latitude],
      },
      'properties': {
        'radius': radius,
        'opacity': opacity,
      },
    }).toList();

    try {
      await _mapController!.addSource(
        'user-spots-pulse-source',
        GeojsonSourceProperties(data: {
          'type': 'FeatureCollection',
          'features': features,
        }),
      );

      if (_mapController == null) return;

      await _mapController!.addCircleLayer(
        'user-spots-pulse-source',
        'user-spots-pulse-layer',
        CircleLayerProperties(
          circleRadius: ['get', 'radius'],
          circleColor: '#E65100',
          circleOpacity: ['get', 'opacity'],
          circleStrokeWidth: 0,
        ),
        belowLayerId: 'spots-layer',
      );
    } catch (e) {
      debugPrint('📍 Explore: Pulse ring update failed: $e');
    }
  }

  // Pin mode methods
  void _enterPinMode() {
    final center = _mapController?.cameraPosition?.target;
    setState(() {
      _isPinMode = true;
      _currentCenter = center;
    });
    ExploreScreen.pinModeActive.value = true;
    HapticFeedback.mediumImpact();
  }

  void _exitPinMode() {
    setState(() {
      _isPinMode = false;
      _currentCenter = null;
    });
    ExploreScreen.pinModeActive.value = false;
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
      await _loadSavedSpots();
    }
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

  // Saved spots sheet (reuses same UX as Gibs)
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
                              setState(() {
                                _rebuildCombinedSpots();
                              });
                              _updateMarkers();
                              _updateVisibleSpots();
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
                      child: _userSpots.isEmpty
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
                              itemCount: _userSpots.length,
                              itemBuilder: (context, index) {
                                final spot = _userSpots[index];
                                final isLoading = spot.shakaScore == null;
                                return _SavedSpotCard(
                                  spot: spot,
                                  isLoading: isLoading,
                                  onTap: isLoading ? null : () {
                                    Navigator.pop(context);
                                    _navigateToUserSpotDetail(spot);
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

  void _navigateToUserSpotDetail(UserSpotResponse spot) {
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
        _userSpots.removeWhere((s) => s.id == spot.id);
      });
      setState(() => _rebuildCombinedSpots());
      await _updateMarkers();
      await _updateVisibleSpots();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${spot.name}"'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete spot'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    // User spots get a cyan border to visually distinguish from curated spots.
    final features = spots.map((spot) {
      final score = spot.shakaScore ?? 0;
      final color = _getScoreColorHex(score);
      final isUser = spot.isUserSpot;
      return {
        'type': 'Feature',
        'properties': {
          'id': spot.id,
          'name': spot.name,
          'score': (spot.shakaScore != null) ? score.toString() : '',
          'sortKey': -score,
          'color': color,
          'radius': isUser ? 15 : 14,
          'strokeWidth': isUser ? 2.5 : 2,
          'strokeColor': isUser ? '#E65100' : '#FFFFFF',
          'textSize': 11,
          'isUserSpot': isUser,
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
      
      // Score labels visible from zoom 6; textPadding matches circle radius so
      // collision zone = visual circle. Higher scores win (sortKey negated above).
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
          textPadding: 14,
          symbolSortKey: ['get', 'sortKey'],
        ),
        minzoom: 6,
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

  /// Highlight the selected spot on the map with a glow ring behind it.
  Future<void> _updateSelectedMarker() async {
    if (_mapController == null) return;

    // Remove old highlight
    try { await _mapController?.removeLayer('selected-spot-layer'); } catch (_) {}
    try { await _mapController?.removeSource('selected-spot-source'); } catch (_) {}

    if (_mapController == null) return;
    if (_selectedSpotIndex == null || _selectedSpotIndex! >= _visibleSpots.length) return;

    final spot = _visibleSpots[_selectedSpotIndex!];
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [spot.coordinates.lon, spot.coordinates.lat],
          },
          'properties': {},
        },
      ],
    };

    try {
      await _mapController!.addSource(
        'selected-spot-source',
        GeojsonSourceProperties(data: geojson),
      );

      if (_mapController == null) return;

      await _mapController!.addCircleLayer(
        'selected-spot-source',
        'selected-spot-layer',
        const CircleLayerProperties(
          circleRadius: 24,
          circleColor: '#7A9BB8',
          circleOpacity: 0.25,
          circleStrokeColor: '#7A9BB8',
          circleStrokeWidth: 2.5,
          circleStrokeOpacity: 0.7,
        ),
        belowLayerId: 'spots-layer',
      );
    } catch (e) {
      debugPrint('Failed to update selected marker: $e');
    }
  }

  void _onSpotSelected(int index) {
    if (index == _selectedSpotIndex) return;
    
    // Check marker tap flag BEFORE haptic to avoid double-buzz
    if (_isFromMarkerTap) {
      _isFromMarkerTap = false;
      setState(() => _selectedSpotIndex = index);
      _updateSelectedMarker();
      return;
    }
    
    HapticFeedback.selectionClick();
    setState(() => _selectedSpotIndex = index);
    _updateSelectedMarker();
    
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
      _updateSelectedMarker();
      
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
    // Block navigation for user spots still loading scores
    if (spot.isUserSpot && spot.shakaScore == null) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still getting intel on this spot...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {
      'date': today,
      if (spot.isUserSpot) 'isUserSpot': true,
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
    
    // Pin mode: full-screen map. Normal: 70% map / 30% carousel
    final mapHeight = _isPinMode ? screenHeight : screenHeight * 0.70;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          Column(
            children: [
              // Map section (full-screen in pin mode, 70% otherwise)
              SizedBox(
                height: mapHeight,
                child: Stack(
                  children: [
                    // Build map only after initial center is resolved (avoids cold-start animateCamera crash)
                    if (_initialCenterReady)
                      Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (event) {
                          _pointerDownPosition = event.localPosition;
                          _pointerDownTime = DateTime.now();
                        },
                        onPointerUp: (event) {
                          final downPos = _pointerDownPosition;
                          final downTime = _pointerDownTime;
                          _pointerDownPosition = null;
                          _pointerDownTime = null;
                          if (downPos == null || downTime == null) return;
                          final duration = DateTime.now().difference(downTime);
                          final distance = (event.localPosition - downPos).distance;
                          if (duration.inMilliseconds < 300 && distance < 20) {
                            if (!_isPinMode) {
                              debugPrint('TAP DETECTED at ${event.localPosition}');
                              _handleMapTap(event.localPosition);
                            }
                          }
                        },
                        onPointerMove: (event) {
                          if (_isPinMode && _mapController != null) {
                            final pos = _mapController!.cameraPosition;
                            if (pos != null && (_currentCenter == null || 
                                pos.target.latitude != _currentCenter!.latitude ||
                                pos.target.longitude != _currentCenter!.longitude)) {
                              setState(() => _currentCenter = pos.target);
                            }
                          }
                        },
                        child: MaplibreMap(
                          key: ValueKey('map_$_mapKey'),
                          onMapCreated: _onMapCreated,
                          onStyleLoadedCallback: _onStyleLoaded,
                          onCameraIdle: () {
                            _onCameraIdle();
                            _onCameraMove();
                          },
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

                    // GPS Coordinates Display (centered at top when in pin mode)
                    if (_isPinMode && _currentCenter != null)
                      Positioned(
                        top: topPadding + 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
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
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
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
                    
                    // Background picker button (left-aligned, hidden in pin mode)
                    if (!_isPinMode)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: _buildBackgroundButton(),
                      ),

                    // Right floating buttons: Saved Spots + Pin (hidden in pin mode)
                    if (!_isPinMode)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: _buildRightFloatingButtons(),
                      ),
                    
                    // Pin mode action buttons (bottom of map)
                    if (_isPinMode)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: bottomPadding + 16,
                        child: _buildPinModeActions(),
                      ),
                    
                    // Loading overlay - show until initial center resolved, then until spots + markers + carousel ready
                    if (!_initialCenterReady || _isLoading || !_mapFullyReady)
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
              
              // Carousel section (hidden in pin mode)
              if (!_isPinMode)
                Expanded(
                  child: Container(
                    color: const Color(0xFF0D0D0D),
                    child: !_mapFullyReady
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
                                      'No spots in view — pan or zoom the map',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : _buildSpotCarousel(),
                  ),
                ),
            ],
          ),

        ],
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

  /// Right floating buttons: Saved Spots (top) + Pin/Add spot (bottom)
  Widget _buildRightFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Saved spots button
        _buildFloatingButton(
          icon: Icons.bookmark_outline,
          onTap: _showSavedSpotsSheet,
          badgeCount: _userSpots.length,
        ),
        const SizedBox(height: 8),
        // Pin/Add spot button
        _buildFloatingButton(
          icon: Icons.add_location_alt,
          onTap: _enterPinMode,
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
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, color: Colors.white70, size: 22),
            ),
            if (badgeCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.info,
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

  /// Pin mode cancel/mark spot buttons — dark opaque backgrounds for visibility on any map style
  Widget _buildPinModeActions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D).withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _exitPinMode,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
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
            child: GestureDetector(
              onTap: _confirmPinLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    'Mark Spot',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Text(
                '${_visibleSpots.length} spots in view',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
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
        
        // Carousel dots
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
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
    final isLoading = spot.isUserSpot && spot.shakaScore == null;
    
    return Opacity(
      opacity: isLoading ? 0.7 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: spot.isUserSpot ? const Color(0xFFE65100).withOpacity(0.4) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            // Score badge or loading spinner
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
                    : isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE65100),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spot.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Saved spot indicator
                      if (spot.isUserSpot)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.bookmark, color: Color(0xFFE65100), size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (isLoading)
                    Text(
                      'Getting intel on this spot...',
                      style: TextStyle(
                        color: const Color(0xFFE65100),
                        fontSize: 12,
                      ),
                    )
                  else ...[
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
                ],
              ),
            ),
            
            // Chevron hint
            const Icon(Icons.chevron_right, color: Colors.white38, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Card for saved spot in bottom sheet (same as Gibs _SavedSpotCard)
class _SavedSpotCard extends StatelessWidget {
  final UserSpotResponse spot;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final bool isLoading;

  const _SavedSpotCard({
    required this.spot,
    required this.onTap,
    required this.onDelete,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasScore = spot.shakaScore != null;
    final scoreColor = hasScore 
        ? AppColors.getScoreColor(spot.shakaScore!) 
        : Colors.grey;
    
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isLoading ? 0.7 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Score badge or loading spinner
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scoreColor.withOpacity(0.5), width: 1),
                ),
                child: Center(
                  child: hasScore
                      ? Text(
                          '${spot.shakaScore}',
                          style: TextStyle(
                            color: scoreColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE65100),
                              ),
                            )
                          : Icon(
                              Icons.location_on,
                              color: scoreColor,
                              size: 20,
                            ),
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
                      isLoading
                          ? 'Getting intel on this spot...'
                          : '${spot.latitude.toStringAsFixed(4)}°, ${spot.longitude.toStringAsFixed(4)}°',
                      style: TextStyle(
                        color: isLoading ? const Color(0xFFE65100) : Colors.white54,
                        fontSize: 12,
                        fontFamily: isLoading ? null : 'monospace',
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
      ),
    );
  }
}

/// Rifle scope style reticle for pin mode (same as Gibs)
class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    final gap = 12.0;
    final lineLength = radius - gap - 4;
    
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    
    for (final paint in [outlinePaint, linePaint]) {
      canvas.drawLine(
        Offset(center.dx, center.dy - gap),
        Offset(center.dx, center.dy - gap - lineLength),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy + gap),
        Offset(center.dx, center.dy + gap + lineLength),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx - gap, center.dy),
        Offset(center.dx - gap - lineLength, center.dy),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx + gap, center.dy),
        Offset(center.dx + gap + lineLength, center.dy),
        paint,
      );
    }
    
    final dotPaint = Paint()..color = Colors.red;
    canvas.drawCircle(center, 3, dotPaint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
