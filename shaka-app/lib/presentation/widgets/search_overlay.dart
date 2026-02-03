import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/shaka_api_client.dart';
import '../../data/models/spot_models.dart';

/// Full-screen search overlay with type-ahead suggestions
class SearchOverlay extends StatefulWidget {
  final Function(SpotSearchResult) onSpotSelected;
  final Function(RegionInfo) onRegionSelected;
  final VoidCallback onClose;

  const SearchOverlay({
    super.key,
    required this.onSpotSelected,
    required this.onRegionSelected,
    required this.onClose,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _apiClient = ShakaApiClient();
  
  List<SpotSearchResult> _spotResults = [];
  List<RegionInfo> _regionResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  Timer? _debounce;

  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF2A2A2A);

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _loadRegions();
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    if (mounted) {
      setState(() => _recentSearches = searches);
    }
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 5) searches.removeLast();
    await prefs.setStringList('recent_searches', searches);
    if (mounted) {
      setState(() => _recentSearches = searches);
    }
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
    if (mounted) {
      setState(() => _recentSearches = []);
    }
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await _apiClient.getRegions();
      if (mounted) {
        setState(() => _regionResults = regions);
      }
    } catch (e) {
      // Ignore - regions are optional
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _spotResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await _apiClient.searchSpotsByName(query: query, limit: 10);
      if (mounted && _controller.text == query) {
        setState(() {
          _spotResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectSpot(SpotSearchResult spot) {
    HapticFeedback.selectionClick();
    _saveRecentSearch(spot.name);
    widget.onSpotSelected(spot);
  }

  void _selectRegion(RegionInfo region) {
    HapticFeedback.selectionClick();
    _saveRecentSearch(region.name);
    widget.onRegionSelected(region);
  }

  void _searchFromRecent(String query) {
    _controller.text = query;
    _onSearchChanged(query);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Material(
      color: _bgColor,
      child: Column(
        children: [
          // Search header
          Container(
            padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 8),
            decoration: const BoxDecoration(
              color: _bgColor,
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search spots or regions...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(left: 12, right: 8),
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _controller.clear();
                      _onSearchChanged('');
                    },
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final query = _controller.text.trim();

    // Loading state
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.info,
        ),
      );
    }

    // Show results if we have a query
    if (query.isNotEmpty) {
      if (_spotResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              Text(
                'No spots found for "$query"',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _spotResults.length,
        itemBuilder: (context, index) {
          final spot = _spotResults[index];
          return _buildSpotTile(spot);
        },
      );
    }

    // Empty state - show recent searches and regions
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Recent searches
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RECENT',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                GestureDetector(
                  onTap: _clearRecentSearches,
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: AppColors.info,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._recentSearches.map((search) => ListTile(
                leading: const Icon(Icons.history, color: Colors.white38, size: 20),
                title: Text(
                  search,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                onTap: () => _searchFromRecent(search),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                dense: true,
              )),
          const SizedBox(height: 16),
        ],

        // Regions
        if (_regionResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'REGIONS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ..._regionResults.map((region) => _buildRegionTile(region)),
        ],
      ],
    );
  }

  Widget _buildSpotTile(SpotSearchResult spot) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _getScoreColor(spot.shakaScore).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _getScoreColor(spot.shakaScore)),
        ),
        child: Center(
          child: Text(
            '${spot.shakaScore}',
            style: TextStyle(
              color: _getScoreColor(spot.shakaScore),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        spot.name,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        spot.region,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
      onTap: () => _selectSpot(spot),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildRegionTile(RegionInfo region) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor),
        ),
        child: const Center(
          child: Icon(Icons.place_outlined, color: Colors.white54, size: 18),
        ),
      ),
      title: Text(
        region.name,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        '${region.spotCount} spots',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
      onTap: () => _selectRegion(region),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Color _getScoreColor(int score) => AppColors.getScoreColor(score);
}
