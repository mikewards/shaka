import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LocationPicker extends StatelessWidget {
  final String selectedLocationName;
  final Function(double lat, double lon, String name) onLocationSelected;

  const LocationPicker({
    super.key,
    required this.selectedLocationName,
    required this.onLocationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLocationPicker(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.oceanBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on,
                color: AppColors.oceanBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                selectedLocationName.isEmpty
                    ? 'Select location'
                    : selectedLocationName,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: selectedLocationName.isEmpty
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LocationPickerSheet(
        onLocationSelected: onLocationSelected,
      ),
    );
  }
}

class _LocationPickerSheet extends StatelessWidget {
  final Function(double lat, double lon, String name) onLocationSelected;

  const _LocationPickerSheet({required this.onLocationSelected});

  // Popular spearfishing locations
  static const _popularLocations = [
    {'name': 'Oahu, Hawaii', 'lat': 21.4389, 'lon': -158.0001},
    {'name': 'Kona, Hawaii', 'lat': 19.6400, 'lon': -155.9969},
    {'name': 'La Jolla, California', 'lat': 32.8328, 'lon': -117.2713},
    {'name': 'Catalina Island, California', 'lat': 33.3872, 'lon': -118.4165},
    {'name': 'Florida Keys', 'lat': 24.5551, 'lon': -81.7800},
    {'name': 'Cabo San Lucas, Mexico', 'lat': 22.8905, 'lon': -109.9167},
    {'name': 'Nassau, Bahamas', 'lat': 25.0480, 'lon': -77.3554},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Select Location',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Use Current Location
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () {
                // TODO: Implement geolocation
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.oceanBlue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.oceanBlue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.my_location, color: AppColors.oceanBlue),
                    const SizedBox(width: 12),
                    Text(
                      'Use Current Location',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.oceanBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Popular Locations
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'POPULAR SPOTS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _popularLocations.length,
              itemBuilder: (context, index) {
                final location = _popularLocations[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.sand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.place,
                      color: AppColors.oceanBlue,
                      size: 20,
                    ),
                  ),
                  title: Text(location['name'] as String),
                  onTap: () {
                    onLocationSelected(
                      location['lat'] as double,
                      location['lon'] as double,
                      location['name'] as String,
                    );
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
