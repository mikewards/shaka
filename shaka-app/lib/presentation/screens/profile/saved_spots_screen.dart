import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../../core/theme/app_colors.dart';

/// Full-screen list of user's saved spots (opened from Profile).
class SavedSpotsScreen extends StatefulWidget {
  const SavedSpotsScreen({super.key});

  @override
  State<SavedSpotsScreen> createState() => _SavedSpotsScreenState();
}

class _SavedSpotsScreenState extends State<SavedSpotsScreen> {
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
    debugPrint('📍 SavedSpots: Loading saved spots...');
    try {
      final response = await _apiClient.getUserSpots();
      if (mounted) {
        setState(() {
          _savedSpots = response.spots;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('📍 SavedSpots: ERROR - $e');
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
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Saved Spots',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _buildContent(),
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
            const Icon(Icons.error_outline, color: AppColors.darkTextHint, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.darkTextMuted)),
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
            const Icon(Icons.bookmark_border, color: AppColors.darkTextHint, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No saved spots yet',
              style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Save spots from the Explore or Satellite Imagery map',
              style: TextStyle(
                  color: AppColors.darkTextHint, fontSize: 13),
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
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.darkTextHint, size: 20),
          ],
        ),
      ),
    );
  }
}
