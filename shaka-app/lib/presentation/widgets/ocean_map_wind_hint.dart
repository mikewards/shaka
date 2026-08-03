import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/wind_format.dart';

/// One-time dismissible caption for the ECMWF wind layer on ocean maps.
/// Shared prefs key is global so dismissing on either surface sticks.
class OceanMapWindHint extends StatefulWidget {
  const OceanMapWindHint({super.key});

  static const prefsKey = 'ocean_map_wind_offshore_hint_dismissed';

  @override
  State<OceanMapWindHint> createState() => _OceanMapWindHintState();
}

class _OceanMapWindHintState extends State<OceanMapWindHint> {
  bool? _visible; // null = still loading prefs

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _visible = !(prefs.getBool(OceanMapWindHint.prefsKey) ?? false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _visible = true);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OceanMapWindHint.prefsKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_visible != true) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 13, color: Colors.white70),
          const SizedBox(width: 6),
          const Flexible(
            child: Text(
              WindFormat.mapWindHint,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
