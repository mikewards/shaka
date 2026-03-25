import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../data/api/shaka_api_client.dart';
import '../../../data/models/spot_models.dart';
import '../../../data/services/map_home_service.dart';
import '../../../data/services/unit_preference_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/location_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<UserSpotResponse> _savedSpots = [];
  bool _isLoadingSpots = true;
  MapHomeLocation? _mapHome;
  bool _isLoadingMapHome = true;

  final _apiClient = ShakaApiClient();

  @override
  void initState() {
    super.initState();
    UnitPreferenceService().addListener(_onUnitChanged);
    _loadSavedSpotsCount();
    _loadMapHome();
  }

  void _onUnitChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UnitPreferenceService().removeListener(_onUnitChanged);
    super.dispose();
  }

  Future<void> _loadSavedSpotsCount() async {
    try {
      final response = await _apiClient.getUserSpots();
      if (mounted) {
        setState(() {
          _savedSpots = response.spots;
          _isLoadingSpots = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _savedSpots = [];
          _isLoadingSpots = false;
        });
      }
    }
  }

  Future<void> _loadMapHome() async {
    final location = await MapHomeService().getMapHome();
    if (mounted) {
      setState(() {
        _mapHome = location;
        _isLoadingMapHome = false;
      });
    }
  }

  void _openMapHomePicker() {
    HapticFeedback.lightImpact();
    showLocationPickerSheet(
      context,
      onLocationSelected: (lat, lon, name) async {
        await MapHomeService().setMapHome(lat, lon);
        if (mounted) {
          setState(() => _mapHome = MapHomeLocation(lat: lat, lon: lon));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Map Home set to $name'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Section label
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // Map Home row
          _ProfileRow(
            icon: Icons.home_outlined,
            iconColor: AppColors.info,
            title: 'Map Home',
            subtitle: _isLoadingMapHome
                ? 'Loading...'
                : (_mapHome?.displaySubtitle ?? 'Not set — tap to choose'),
            onTap: _openMapHomePicker,
          ),
          const SizedBox(height: 12),
          // Units row with inline toggle
          _UnitToggleRow(),
          const SizedBox(height: 12),
          // Saved Spots row (single row; tap opens full list)
          _ProfileRow(
            icon: Icons.bookmark_border,
            iconColor: AppColors.scoreExcellent,
            title: 'My Spots',
            subtitle: _isLoadingSpots
                ? 'Loading...'
                : '${_savedSpots.length} spot${_savedSpots.length == 1 ? '' : 's'}',
            onTap: () async {
              HapticFeedback.lightImpact();
              await context.push('/profile/saved-spots');
              if (mounted) _loadSavedSpotsCount();
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _UnitToggleRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final units = UnitPreferenceService();
    return Container(
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
              color: AppColors.info.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.straighten, color: AppColors.info, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Units',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Segmented toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SegmentButton(
                  label: '°F ft kts',
                  isSelected: units.isImperial,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    units.setSystem(UnitSystem.imperial);
                  },
                ),
                _SegmentButton(
                  label: '°C m km/h',
                  isSelected: units.isMetric,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    units.setSystem(UnitSystem.metric);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.info.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelected ? AppColors.info.withOpacity(0.4) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.info : AppColors.darkTextMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
