import 'package:shared_preferences/shared_preferences.dart';

class ReportsPreferences {
  final Set<String> hiddenSpecies;
  final Set<String> pinnedSpecies;
  final List<String> manualOrder;

  const ReportsPreferences({
    required this.hiddenSpecies,
    required this.pinnedSpecies,
    required this.manualOrder,
  });

  static const empty = ReportsPreferences(
    hiddenSpecies: <String>{},
    pinnedSpecies: <String>{},
    manualOrder: <String>[],
  );

  ReportsPreferences copyWith({
    Set<String>? hiddenSpecies,
    Set<String>? pinnedSpecies,
    List<String>? manualOrder,
  }) {
    return ReportsPreferences(
      hiddenSpecies: hiddenSpecies ?? this.hiddenSpecies,
      pinnedSpecies: pinnedSpecies ?? this.pinnedSpecies,
      manualOrder: manualOrder ?? this.manualOrder,
    );
  }
}

class ReportsPreferencesRepository {
  static String _hiddenKey(String regionId) =>
      'reports_hidden_species_$regionId';
  static String _pinnedKey(String regionId) =>
      'reports_pinned_species_$regionId';
  static String _orderKey(String regionId) => 'reports_species_order_$regionId';

  Future<ReportsPreferences> load(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    final hidden =
        prefs.getStringList(_hiddenKey(regionId)) ?? const <String>[];
    final pinned =
        prefs.getStringList(_pinnedKey(regionId)) ?? const <String>[];
    final order = prefs.getStringList(_orderKey(regionId)) ?? const <String>[];

    return ReportsPreferences(
      hiddenSpecies: hidden.toSet(),
      pinnedSpecies: pinned.toSet(),
      manualOrder: List<String>.from(order),
    );
  }

  Future<void> saveHiddenSpecies(String regionId, Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenKey(regionId), hidden.toList()..sort());
  }

  Future<void> savePinnedSpecies(String regionId, Set<String> pinned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedKey(regionId), pinned.toList()..sort());
  }

  Future<void> saveManualOrder(
      String regionId, List<String> manualOrder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey(regionId), manualOrder);
  }

  Future<void> clearAll(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hiddenKey(regionId));
    await prefs.remove(_pinnedKey(regionId));
    await prefs.remove(_orderKey(regionId));
  }
}
