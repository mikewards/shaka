import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/map_home_service.dart';
import 'location_picker.dart';

/// Shown on first app launch when Map Home is not set.
/// Prompts user to pin their default location for Explore and Gibs maps.
class SetMapHomeDialog extends StatelessWidget {
  const SetMapHomeDialog({super.key});

  static const _bgColor = Color(0xFF1A1A1A);

  /// Call when Explore (or app shell) has determined Map Home is not set.
  static Future<void> showIfNeeded(BuildContext context) async {
    final service = MapHomeService();
    if (!await service.isMapHomeSet()) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const SetMapHomeDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Dialog(
      backgroundColor: _bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding.clamp(0.0, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.map_outlined,
              color: AppColors.info,
              size: 40,
            ),
            const SizedBox(height: 16),
            const Text(
              'Set your Map Home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Choose where your Explore map and Satellite map will open by default. You can change this anytime in Profile.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final navigator = Navigator.of(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  navigator.pop();
                  showLocationPickerSheet(
                    navigator.context,
                    onLocationSelected: (lat, lon, name) async {
                      await MapHomeService().setMapHome(lat, lon);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('Map Home set to $name'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Choose location'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
