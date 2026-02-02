import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../../core/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<UserSpotResponse> _savedSpots = [];
  bool _isLoading = true;
  String? _error;
  
  final _apiClient = ShakaApiClient();

  @override
  void initState() {
    super.initState();
    _loadSavedSpots();
  }

  Future<void> _loadSavedSpots() async {
    try {
      final response = await _apiClient.getUserSpots();
      if (mounted) {
        setState(() {
          _savedSpots = response.spots;
          _isLoading = false;
        });
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

  void _navigateToSpot(UserSpotResponse spot) {
    final today = DateTime.now();
    final date = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    context.push('/spot/${spot.id}', extra: {
      'date': date,
      'isUserSpot': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Saved Spots Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Text(
                  'SAVED SPOTS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (!_isLoading && _error == null)
                  Text(
                    '${_savedSpots.length} spots',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.darkAccent),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadSavedSpots();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    if (_savedSpots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_border, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No saved spots yet',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Save spots from the Satellite Imagery map',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadSavedSpots,
      color: AppColors.darkAccent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _savedSpots.length,
        itemBuilder: (context, index) {
          final spot = _savedSpots[index];
          return _ProfileSpotCard(
            spot: spot,
            onTap: () => _navigateToSpot(spot),
          );
        },
      ),
    );
  }
}

class _ProfileSpotCard extends StatelessWidget {
  final UserSpotResponse spot;
  final VoidCallback onTap;

  const _ProfileSpotCard({required this.spot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.scoreExcellent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.location_on,
                color: AppColors.scoreExcellent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
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
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}
