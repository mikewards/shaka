import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
                    ? 'Tap to select location'
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
  final MapController _mapController = MapController();

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
    // California
    '92037': {'lat': 32.8328, 'lon': -117.2713, 'name': 'La Jolla, CA'},
    '92118': {'lat': 32.6800, 'lon': -117.2400, 'name': 'Coronado, CA'},
    '90704': {'lat': 33.3872, 'lon': -118.4165, 'name': 'Avalon (Catalina), CA'},
    '93001': {'lat': 34.2750, 'lon': -119.2290, 'name': 'Ventura, CA'},
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

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedPoint = point;
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

          // Zip Code Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _zipController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter zip code',
                prefixIcon: const Icon(Icons.pin_drop, color: AppColors.oceanBlue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _onZipSubmit(_zipController.text),
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              onSubmitted: _onZipSubmit,
            ),
          ),

          const SizedBox(height: 16),

          // Map Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () => setState(() => _showMap = !_showMap),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _showMap ? AppColors.oceanBlue.withOpacity(0.1) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _showMap ? AppColors.oceanBlue : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.map,
                      color: _showMap ? AppColors.oceanBlue : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _showMap ? 'Tap map to drop pin' : 'Drop pin on map',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _showMap ? AppColors.oceanBlue : AppColors.textPrimary,
                        fontWeight: _showMap ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showMap ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Map View
          if (_showMap) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(21.4389, -158.0001), // Oahu
                      initialZoom: 5,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.shaka.shaka',
                      ),
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_on,
                                color: AppColors.coral,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_selectedPoint != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _confirmMapSelection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.oceanBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Use this location (${_selectedPoint!.latitude.toStringAsFixed(2)}, ${_selectedPoint!.longitude.toStringAsFixed(2)})',
                    ),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 16),

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
          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _popularLocations.length,
              itemBuilder: (context, index) {
                final location = _popularLocations[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.sand,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.place,
                      color: AppColors.oceanBlue,
                      size: 16,
                    ),
                  ),
                  title: Text(
                    location['name'] as String,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    widget.onLocationSelected(
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
