import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem { metric, imperial }

/// Service for managing unit system preference across the app.
/// Singleton pattern with ChangeNotifier for reactive updates.
class UnitPreferenceService extends ChangeNotifier {
  static final UnitPreferenceService _instance = UnitPreferenceService._internal();
  factory UnitPreferenceService() => _instance;
  UnitPreferenceService._internal();

  static const _key = 'unit_system';
  UnitSystem _system = UnitSystem.imperial;
  UnitSystem get system => _system;
  bool get isMetric => _system == UnitSystem.metric;
  bool get isImperial => _system == UnitSystem.imperial;

  /// Initialize from saved preference
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored == 'metric') _system = UnitSystem.metric;
    } catch (e) {
      debugPrint('Failed to load unit preference: $e');
    }
  }

  /// Set the unit system
  Future<void> setSystem(UnitSystem system) async {
    if (_system == system) return;
    _system = system;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, system.name);
    } catch (e) {
      debugPrint('Failed to save unit preference: $e');
    }
  }

  /// Toggle between metric and imperial
  Future<void> toggle() async {
    await setSystem(isMetric ? UnitSystem.imperial : UnitSystem.metric);
  }
}
