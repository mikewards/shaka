import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/map_background_service.dart';

/// Location picker with Quiet Luxury styling.
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
    showLocationPickerSheet(context, onLocationSelected: onLocationSelected);
  }
}

/// Shows the location picker as a modal sheet (e.g. for setting Map Home).
/// Styled to match app dark theme. "Drop pin on map" opens full map + reticle like Gibs.
void showLocationPickerSheet(
  BuildContext context, {
  required void Function(double lat, double lon, String name) onLocationSelected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _LocationPickerSheet(
      onLocationSelected: onLocationSelected,
    ),
  );
}

// Dark theme constants matching app (app_colors.dart)
const _sheetBg = Color(0xFF1A1A1A);
const _sheetBorder = Color(0xFF2A2A2A);

class _LocationPickerSheet extends StatefulWidget {
  final Function(double lat, double lon, String name) onLocationSelected;

  const _LocationPickerSheet({required this.onLocationSelected});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  LatLng _currentCenter = const LatLng(21.4389, -158.0001);

  static const _popularLocations = [
    {'name': 'Oahu North Shore, Hawaii', 'lat': 21.6400, 'lon': -158.0600},
    {'name': 'Oahu West Side, Hawaii', 'lat': 21.4000, 'lon': -158.1500},
    {'name': 'Kona, Big Island', 'lat': 19.6400, 'lon': -155.9969},
    {'name': 'Maui', 'lat': 20.8000, 'lon': -156.3200},
    {'name': 'La Jolla, California', 'lat': 32.8328, 'lon': -117.2713},
    {'name': 'Catalina Island', 'lat': 33.3872, 'lon': -118.4165},
    {'name': 'Channel Islands', 'lat': 34.0167, 'lon': -119.4000},
    {'name': 'Florida Keys - Marathon', 'lat': 24.7136, 'lon': -81.0906},
    {'name': 'Florida Keys - Key West', 'lat': 24.5551, 'lon': -81.7800},
    {'name': 'Nassau, Bahamas', 'lat': 25.0480, 'lon': -77.3554},
    {'name': 'Cabo San Lucas', 'lat': 22.8905, 'lon': -109.9167},
    {'name': 'Cozumel', 'lat': 20.4230, 'lon': -86.9223},
  ];

  void _enterPinMode() {
    HapticFeedback.mediumImpact();
    final initialCenter = _currentCenter;
    final onLocationSelected = widget.onLocationSelected;
    // Use full-screen route so map gets pan gestures (bottom sheet would steal drag).
    Navigator.of(context).pop();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _DropPinScreen(
          initialCenter: initialCenter,
          onLocationSelected: onLocationSelected,
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.9;
    // List view: header + "Drop pin on map" + popular spots (dark theme, no zip field)
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: _sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.darkBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Select Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Drop pin on map row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: _enterPinMode,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.info.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.map, color: AppColors.info, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'Drop pin on map',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right, color: Colors.white54, size: 24),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'POPULAR SPOTS',
                style: TextStyle(
                  letterSpacing: 2,
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onLocationSelected(
                        location['lat'] as double,
                        location['lon'] as double,
                        location['name'] as String,
                      );
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.darkBorder,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.place,
                              color: AppColors.info,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              location['name'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                        ],
                      ),
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

/// Full-screen drop-pin map so pan gestures go to the map (not a bottom sheet).
class _DropPinScreen extends StatefulWidget {
  final LatLng initialCenter;
  final void Function(double lat, double lon, String name) onLocationSelected;
  final VoidCallback onCancel;

  const _DropPinScreen({
    required this.initialCenter,
    required this.onLocationSelected,
    required this.onCancel,
  });

  @override
  State<_DropPinScreen> createState() => _DropPinScreenState();
}

class _DropPinScreenState extends State<_DropPinScreen> {
  MapLibreMapController? _mapController;
  late LatLng _currentCenter;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialCenter;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  void _onCameraIdle() {
    if (_mapController == null) return;
    final pos = _mapController!.cameraPosition;
    if (pos != null) setState(() => _currentCenter = pos.target);
  }

  void _updateCenterFromCamera() {
    if (_mapController == null) return;
    final pos = _mapController!.cameraPosition;
    if (pos != null &&
        (pos.target.latitude != _currentCenter.latitude ||
            pos.target.longitude != _currentCenter.longitude)) {
      setState(() => _currentCenter = pos.target);
    }
  }

  void _confirm() {
    HapticFeedback.lightImpact();
    widget.onLocationSelected(
      _currentCenter.latitude,
      _currentCenter.longitude,
      '${_currentCenter.latitude.toStringAsFixed(4)}°, ${_currentCenter.longitude.toStringAsFixed(4)}°',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    // Place coords well below status bar / Dynamic Island (avoid camera overlap)
    const coordTopExtra = 28.0;
    final coordTop = topPadding + coordTopExtra;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: (_) => _updateCenterFromCamera(),
              child: MapLibreMap(
                onMapCreated: _onMapCreated,
                onCameraIdle: _onCameraIdle,
                trackCameraPosition: true,
                initialCameraPosition: CameraPosition(
                  target: _currentCenter,
                  zoom: 8,
                ),
                styleString: MapBackgroundService.cartoVoyagerStyle,
                compassEnabled: false,
                attributionButtonMargins: const Point(-100, -100),
                logoViewMargins: const Point(-100, -100),
              ),
            ),
          ),
          Positioned(
            top: coordTop,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      '${_currentCenter.latitude.toStringAsFixed(5)}, ${_currentCenter.longitude.toStringAsFixed(5)}',
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
          const Center(
            child: IgnorePointer(
              child: SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(painter: _LocationReticlePainter()),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomSafe + 16,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onCancel();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
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
                      onTap: _confirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Set as Map Home',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Reticle overlay for pin mode (center = selected point).
class _LocationReticlePainter extends CustomPainter {
  const _LocationReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const gap = 12.0;
    final lineLength = size.width / 2 - gap - 4;

    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (final paint in [outlinePaint, linePaint]) {
      canvas.drawLine(Offset(center.dx, center.dy - gap), Offset(center.dx, center.dy - gap - lineLength), paint);
      canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, center.dy + gap + lineLength), paint);
      canvas.drawLine(Offset(center.dx - gap, center.dy), Offset(center.dx - gap - lineLength, center.dy), paint);
      canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(center.dx + gap + lineLength, center.dy), paint);
    }
    canvas.drawCircle(center, 3, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
