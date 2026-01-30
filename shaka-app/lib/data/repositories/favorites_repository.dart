import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_spot.dart';
import '../models/spot_models.dart';

/// Repository for managing saved/favorite dive spots.
/// Uses SharedPreferences for local persistence.
class FavoritesRepository {
  static const _favoritesKey = 'saved_spots';
  
  /// Get all saved spots
  Future<List<SavedSpot>> getSavedSpots() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_favoritesKey) ?? [];
    
    return jsonList
        .map((json) => SavedSpot.fromJson(jsonDecode(json)))
        .toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt)); // Most recent first
  }
  
  /// Check if a spot is saved
  Future<bool> isSpotSaved(String spotId) async {
    final spots = await getSavedSpots();
    return spots.any((s) => s.spotId == spotId);
  }
  
  /// Save a spot to favorites
  Future<void> saveSpot(SavedSpot spot) async {
    final prefs = await SharedPreferences.getInstance();
    final spots = await getSavedSpots();
    
    // Remove if already exists (to update)
    spots.removeWhere((s) => s.spotId == spot.spotId);
    spots.insert(0, spot); // Add to beginning
    
    final jsonList = spots.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_favoritesKey, jsonList);
  }
  
  /// Save a spot from SpotSummary (convenience method)
  Future<void> saveSpotFromSummary(SpotSummary summary, String region) async {
    final spot = SavedSpot(
      spotId: summary.id,
      name: summary.name,
      lat: summary.coordinates.lat,
      lon: summary.coordinates.lon,
      access: summary.access,
      region: region,
      savedAt: DateTime.now(),
    );
    await saveSpot(spot);
  }
  
  /// Save a spot from SpotDetail (convenience method)
  Future<void> saveSpotFromDetail(SpotDetail detail, String region) async {
    final spot = SavedSpot(
      spotId: detail.id,
      name: detail.name,
      lat: detail.coordinates.lat,
      lon: detail.coordinates.lon,
      access: detail.access.type,
      region: region,
      savedAt: DateTime.now(),
    );
    await saveSpot(spot);
  }
  
  /// Remove a spot from favorites
  Future<void> removeSpot(String spotId) async {
    final prefs = await SharedPreferences.getInstance();
    final spots = await getSavedSpots();
    
    spots.removeWhere((s) => s.spotId == spotId);
    
    final jsonList = spots.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_favoritesKey, jsonList);
  }
  
  /// Toggle a spot's saved status
  Future<bool> toggleSaved(SavedSpot spot) async {
    final isSaved = await isSpotSaved(spot.spotId);
    if (isSaved) {
      await removeSpot(spot.spotId);
      return false;
    } else {
      await saveSpot(spot);
      return true;
    }
  }
  
  /// Reorder saved spots (for manual sorting)
  Future<void> reorderSpots(List<SavedSpot> newOrder) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = newOrder.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_favoritesKey, jsonList);
  }
  
  /// Get list of spot IDs only (for batch API calls)
  Future<List<String>> getSavedSpotIds() async {
    final spots = await getSavedSpots();
    return spots.map((s) => s.spotId).toList();
  }
  
  /// Clear all saved spots
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
  }
}
