import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Location picker with Quiet Luxury styling.
/// 
/// Text-based, no icons - clean and minimal.
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
      onTap: () {
        HapticFeedback.lightImpact();
        _showLocationPicker(context);
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
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
            Text(
              '>',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
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

class _LocationPickerSheet extends StatefulWidget {
  final Function(double lat, double lon, String name) onLocationSelected;

  const _LocationPickerSheet({required this.onLocationSelected});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final TextEditingController _zipController = TextEditingController();
  bool _showMap = false;
  LatLng? _selectedPoint;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  // Popular spearfishing locations - expanded list
  static const _popularLocations = [
    // Hawaii
    {'name': 'Oahu North Shore, Hawaii', 'lat': 21.6400, 'lon': -158.0600},
    {'name': 'Oahu West Side, Hawaii', 'lat': 21.4000, 'lon': -158.1500},
    {'name': 'Kona, Big Island', 'lat': 19.6400, 'lon': -155.9969},
    {'name': 'Maui', 'lat': 20.8000, 'lon': -156.3200},
    // California
    {'name': 'La Jolla, California', 'lat': 32.8328, 'lon': -117.2713},
    {'name': 'Catalina Island', 'lat': 33.3872, 'lon': -118.4165},
    {'name': 'Channel Islands', 'lat': 34.0167, 'lon': -119.4000},
    // Florida
    {'name': 'Florida Keys - Marathon', 'lat': 24.7136, 'lon': -81.0906},
    {'name': 'Florida Keys - Key West', 'lat': 24.5551, 'lon': -81.7800},
    // Caribbean
    {'name': 'Nassau, Bahamas', 'lat': 25.0480, 'lon': -77.3554},
    {'name': 'Andros, Bahamas', 'lat': 24.7000, 'lon': -77.7500},
    {'name': 'Exuma, Bahamas', 'lat': 24.1833, 'lon': -76.4667},
    // Mexico
    {'name': 'Cabo San Lucas', 'lat': 22.8905, 'lon': -109.9167},
    {'name': 'Cozumel', 'lat': 20.4230, 'lon': -86.9223},
    // Pacific
    {'name': 'Fakarava, French Polynesia', 'lat': -16.4500, 'lon': -145.4500},
    {'name': 'Rangiroa, French Polynesia', 'lat': -14.9500, 'lon': -147.6167},
    // Mediterranean
    {'name': 'Sardinia, Italy', 'lat': 40.5667, 'lon': 8.1667},
    {'name': 'Corsica, France', 'lat': 42.3667, 'lon': 8.5500},
    // Australia
    {'name': 'Ningaloo Reef, Australia', 'lat': -22.6833, 'lon': 113.6667},
  ];

  // Zip code to coordinates mapping (US focused)
  static const _zipToCoords = {
    // Hawaii
    '96712': {'lat': 21.6400, 'lon': -158.0600, 'name': 'Haleiwa, HI'},
    '96791': {'lat': 21.4500, 'lon': -158.1800, 'name': 'Waianae, HI'},
    '96740': {'lat': 19.6400, 'lon': -155.9969, 'name': 'Kailua-Kona, HI'},
    '96761': {'lat': 20.8800, 'lon': -156.6800, 'name': 'Lahaina, HI'},
    '96753': {'lat': 20.7300, 'lon': -156.4500, 'name': 'Kihei, HI'},
    '96734': {'lat': 21.4000, 'lon': -157.7400, 'name': 'Kailua, HI'},
    // California - San Francisco Bay Area
    '94102': {'lat': 37.7749, 'lon': -122.4194, 'name': 'San Francisco, CA'},
    '94110': {'lat': 37.7485, 'lon': -122.4156, 'name': 'San Francisco (Mission), CA'},
    '94122': {'lat': 37.7585, 'lon': -122.4844, 'name': 'San Francisco (Sunset), CA'},
    '94965': {'lat': 37.8558, 'lon': -122.4892, 'name': 'Sausalito, CA'},
    '94019': {'lat': 37.5021, 'lon': -122.4536, 'name': 'Half Moon Bay, CA'},
    '94060': {'lat': 37.3631, 'lon': -122.4061, 'name': 'Pescadero, CA'},
    '95060': {'lat': 36.9741, 'lon': -122.0308, 'name': 'Santa Cruz, CA'},
    '93940': {'lat': 36.6002, 'lon': -121.8947, 'name': 'Monterey, CA'},
    '93950': {'lat': 36.6177, 'lon': -121.9166, 'name': 'Pacific Grove, CA'},
    '93923': {'lat': 36.5468, 'lon': -121.9234, 'name': 'Carmel, CA'},
    // California - Southern
    '92037': {'lat': 32.8328, 'lon': -117.2713, 'name': 'La Jolla, CA'},
    '92118': {'lat': 32.6800, 'lon': -117.2400, 'name': 'Coronado, CA'},
    '90704': {'lat': 33.3872, 'lon': -118.4165, 'name': 'Avalon (Catalina), CA'},
    '93001': {'lat': 34.2750, 'lon': -119.2290, 'name': 'Ventura, CA'},
    '90266': {'lat': 33.8886, 'lon': -118.4098, 'name': 'Manhattan Beach, CA'},
    '90254': {'lat': 33.8622, 'lon': -118.3990, 'name': 'Hermosa Beach, CA'},
    '90277': {'lat': 33.8153, 'lon': -118.3881, 'name': 'Redondo Beach, CA'},
    '92651': {'lat': 33.5427, 'lon': -117.7854, 'name': 'Laguna Beach, CA'},
    '92661': {'lat': 33.6028, 'lon': -117.9029, 'name': 'Newport Beach, CA'},
    '92648': {'lat': 33.6595, 'lon': -117.9988, 'name': 'Huntington Beach, CA'},
    // Florida Keys
    '33037': {'lat': 25.0861, 'lon': -80.4475, 'name': 'Key Largo, FL'},
    '33050': {'lat': 24.7136, 'lon': -81.0906, 'name': 'Marathon, FL'},
    '33040': {'lat': 24.5551, 'lon': -81.7800, 'name': 'Key West, FL'},
    '33036': {'lat': 24.9100, 'lon': -80.6300, 'name': 'Islamorada, FL'},
    // Florida mainland
    '33139': {'lat': 25.7900, 'lon': -80.1400, 'name': 'Miami Beach, FL'},
    '34102': {'lat': 26.1420, 'lon': -81.7948, 'name': 'Naples, FL'},
  };

  @override
  void dispose() {
    _zipController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onZipSubmit(String zip) {
    final coords = _zipToCoords[zip.trim()];
    if (coords != null) {
      widget.onLocationSelected(
        coords['lat'] as double,
        coords['lon'] as double,
        coords['name'] as String,
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zip not found. Try the map or popular spots.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _markers = {
        Marker(
          markerId: const MarkerId('selected'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });
  }

  void _confirmMapSelection() {
    if (_selectedPoint != null) {
      final name = '${_selectedPoint!.latitude.toStringAsFixed(2)}, ${_selectedPoint!.longitude.toStringAsFixed(2)}';
      widget.onLocationSelected(
        _selectedPoint!.latitude,
        _selectedPoint!.longitude,
        'Custom: $name',
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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

          // Header - text-based close button
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(
                  'Location',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Done',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Zip Code Input with submit button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _zipController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Zip code',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.oceanBlue),
                      ),
                    ),
                    onSubmitted: _onZipSubmit,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _onZipSubmit(_zipController.text);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.oceanBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Go',
                      style: TextStyle(
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Map Toggle - text-based
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _showMap = !_showMap);
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _showMap ? AppColors.oceanBlue.withOpacity(0.05) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _showMap ? AppColors.oceanBlue.withOpacity(0.3) : AppColors.border.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _showMap ? 'Tap to place pin' : 'Use map',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _showMap ? AppColors.oceanBlue : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _showMap ? '−' : '+',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Map View
          if (_showMap) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(21.4389, -158.0001), // Hawaii
                      zoom: 4,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    onTap: _onMapTap,
                    markers: _markers,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapToolbarEnabled: false,
                  ),
                ),
              ),
            ),
            if (_selectedPoint != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _confirmMapSelection();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.oceanBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Confirm',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 20),

          // Popular Locations
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'POPULAR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _popularLocations.length,
              itemBuilder: (context, index) {
                final location = _popularLocations[index];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onLocationSelected(
                      location['lat'] as double,
                      location['lon'] as double,
                      location['name'] as String,
                    );
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          location['name'] as String,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          '>',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
