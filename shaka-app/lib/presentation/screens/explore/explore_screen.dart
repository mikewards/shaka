import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../widgets/search_overlay.dart';

/// Full-screen explore map for discovering dive spots.
/// Surfline-style: Map 70% top, horizontal spot carousel 30% bottom.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final MapController _mapController = MapController();
  final ShakaApiClient _apiClient = ShakaApiClient();
  final PageController _carouselController = PageController(viewportFraction: 0.85);
  
  // Default to Hawaii
  static const _defaultCenter = LatLng(21.3069, -157.8583);
  static const _defaultZoom = 7.5;
  
  List<SpotSummary> _spots = [];
  bool _isLoading = true;
  String? _error;
  int? _selectedSpotIndex = 0; // null = no selection
  String _selectedFilter = 'All';
  bool _showSearch = false;
  
  // Debounce timer for map animations (prevents excessive animations during rapid carousel swiping)
  Timer? _mapAnimationDebounce;
  bool _isFromMarkerTap = false; // Track if selection came from marker tap

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }
  
  @override
  void dispose() {
    _mapAnimationDebounce?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _loadSpots({int retryCount = 0}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await _apiClient.searchSpots(
        lat: _defaultCenter.latitude,
        lon: _defaultCenter.longitude,
        date: today,
        radiusKm: 160, // ~100 miles, reasonable area
      );
      
      if (mounted) {
        setState(() {
          _spots = response.spots;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Auto-retry once on initial load
      if (retryCount < 1 && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        return _loadSpots(retryCount: retryCount + 1);
      }
      
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<SpotSummary> get _filteredSpots {
    if (_selectedFilter == 'All') return _spots;
    if (_selectedFilter == 'Shore') {
      return _spots.where((s) => s.access == 'shore').toList();
    }
    if (_selectedFilter == 'Boat') {
      return _spots.where((s) => s.access == 'boat').toList();
    }
    if (_selectedFilter == '80+') {
      return _spots.where((s) => s.shakaScore >= 80).toList();
    }
    return _spots;
  }

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);

  /// Handle spot selection from carousel swipes (debounced map animation)
  void _onSpotSelected(int index) {
    if (index == _selectedSpotIndex) return;
    
    HapticFeedback.selectionClick();
    setState(() => _selectedSpotIndex = index);
    
    // Skip map animation if triggered from marker tap (already handled)
    if (_isFromMarkerTap) {
      _isFromMarkerTap = false;
      return;
    }
    
    // Debounce map animation for carousel swipes (300ms delay)
    _mapAnimationDebounce?.cancel();
    _mapAnimationDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final spots = _filteredSpots;
      if (index < spots.length) {
        final spot = spots[index];
        _mapController.move(
          LatLng(spot.coordinates.lat, spot.coordinates.lon),
          10.0,
        );
      }
    });
  }
  
  /// Handle spot selection from marker tap (immediate map animation)
  void _onMarkerTapped(int index) {
    if (index == _selectedSpotIndex) return;
    
    _isFromMarkerTap = true;
    HapticFeedback.selectionClick();
    setState(() => _selectedSpotIndex = index);
    
    // Immediate map animation for marker taps
    final spot = _filteredSpots[index];
    _mapController.move(
      LatLng(spot.coordinates.lat, spot.coordinates.lon),
      10.0,
    );
    
    // Sync carousel to marker
    _carouselController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openSpotDetail(SpotSummary spot) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.push('/spot/${spot.id}', extra: {
      'date': today,
      'spot': spot, // Pass preloaded data for instant display
    });
  }
  
  /// Handle filter changes - try to keep current spot if it passes the filter
  void _onFilterChanged(String filter) {
    if (filter == _selectedFilter) return;
    
    HapticFeedback.selectionClick();
    
    // Get currently selected spot before changing filter
    SpotSummary? currentSpot;
    final currentIndex = _selectedSpotIndex;
    if (currentIndex != null && currentIndex < _filteredSpots.length) {
      currentSpot = _filteredSpots[currentIndex];
    }
    
    // Apply the new filter
    setState(() => _selectedFilter = filter);
    
    // Check if current spot is still in filtered list
    final newFilteredSpots = _filteredSpots;
    if (newFilteredSpots.isEmpty) {
      setState(() => _selectedSpotIndex = null);
      return;
    }
    
    // Try to find current spot in new filtered list
    int newIndex = 0;
    if (currentSpot != null) {
      final foundIndex = newFilteredSpots.indexWhere((s) => s.id == currentSpot!.id);
      if (foundIndex >= 0) {
        newIndex = foundIndex;
      }
    }
    
    setState(() => _selectedSpotIndex = newIndex);
    
    // Sync carousel and map (without jarring animation if staying on same spot)
    _carouselController.jumpToPage(newIndex);
    final spot = newFilteredSpots[newIndex];
    _mapController.move(
      LatLng(spot.coordinates.lat, spot.coordinates.lon),
      10.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    // 70% map, 30% carousel
    final mapHeight = screenHeight * 0.65;
    final carouselHeight = screenHeight * 0.35 - bottomPadding;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              // Map section (65%)
              SizedBox(
                height: mapHeight,
                child: Stack(
                  children: [
                    // Map
                    FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: _defaultZoom,
                    minZoom: 3,
                    maxZoom: 18,
                    backgroundColor: const Color(0xFF191A1A),
                    onTap: (_, __) {
                      // Tap on empty map area deselects current spot
                      if (_selectedSpotIndex != null) {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedSpotIndex = null);
                      }
                    },
                  ),
                  children: [
                    // OpenStreetMap with dark styling
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.shaka.app',
                      maxZoom: 19,
                    ),
                    // Spot markers
                    if (_filteredSpots.isNotEmpty)
                      MarkerLayer(
                        markers: _filteredSpots.asMap().entries.map((entry) {
                          final index = entry.key;
                          final spot = entry.value;
                          final isSelected = index == _selectedSpotIndex;
                          
                          return Marker(
                            point: LatLng(spot.coordinates.lat, spot.coordinates.lon),
                            width: isSelected ? 48 : 36,
                            height: isSelected ? 48 : 36,
                            child: GestureDetector(
                              onTap: () => _onMarkerTapped(index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: _getScoreColor(spot.shakaScore),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.white54,
                                    width: isSelected ? 3 : 2,
                                  ),
                                  boxShadow: isSelected ? [
                                    BoxShadow(
                                      color: _getScoreColor(spot.shakaScore).withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ] : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${spot.shakaScore}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: isSelected ? 14 : 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
                
                // Search bar overlay
                Positioned(
                  top: topPadding + 12,
                  left: 16,
                  right: 16,
                  child: _buildSearchBar(),
                ),
                
                // Filter chips
                Positioned(
                  top: topPadding + 68,
                  left: 0,
                  right: 0,
                  child: _buildFilterChips(),
                ),
                
                // Loading indicator
                if (_isLoading)
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
    // Move map to region center
    _mapController.move(
      LatLng(region.centerLat, region.centerLon),
      9.0,
    );
    // Reload spots for this region
    _loadSpotsForRegion(region);
  }

  Future<void> _loadSpotsForRegion(RegionInfo region) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final response = await _apiClient.searchSpots(
        lat: region.centerLat,
        lon: region.centerLon,
        date: today,
        radiusKm: 150,
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

  Widget _buildFilterChips() {
    final filters = ['All', 'Shore', 'Boat', '80+'];
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onFilterChanged(filter),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF5B9BD5).withOpacity(0.25)
                      : const Color(0xFF1A1A1A).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF5B9BD5) : Colors.white24,
                  ),
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF5B9BD5) : Colors.white70,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSpotCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
        
        // Carousel
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
        
        // Page indicator dots
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _filteredSpots.length.clamp(0, 10), // Max 10 dots
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

/// Individual spot card in the carousel - compact design
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
          // Header row: Score + Name + Arrow
          Row(
            children: [
              // Score badge (compact)
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
              // Name and access
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
                    Row(
                      children: [
                        Icon(
                          spot.access == 'boat' ? Icons.sailing : Icons.directions_walk,
                          color: Colors.white54,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          spot.access == 'boat' ? 'Boat' : 'Shore',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
            ],
          ),
          
          const SizedBox(height: 10),
          
          // Conditions row (compact)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ConditionChip(
                icon: Icons.visibility,
                value: spot.conditions.visibility.split(' ').first,
              ),
              _ConditionChip(
                icon: Icons.thermostat,
                value: spot.conditions.waterTemp.split(' ').first,
              ),
              _ConditionChip(
                icon: Icons.waves,
                value: spot.conditions.swell.split('@').first.trim(),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38, size: 12),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
