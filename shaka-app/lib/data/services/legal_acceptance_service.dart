import 'package:shared_preferences/shared_preferences.dart';
import '../../core/legal/legal_content.dart';

/// Tracks whether the user has accepted the current Terms/Privacy version.
///
/// For now this is a local mirror (shared_preferences) that drives the
/// first-launch acceptance gate instantly and offline. It is reworked later
/// to treat the server-side `legal_acceptances` record as the source of
/// truth, keeping this local value as a cache.
class LegalAcceptanceService {
  static const String _versionKey = 'legal_accepted_version';
  static const String _timestampKey = 'legal_accepted_at';

  /// True if the user has accepted the version currently in effect.
  static Future<bool> hasAcceptedCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getString(_versionKey);
    return accepted == LegalContent.currentLegalVersion;
  }

  /// Records acceptance of the current legal version locally.
  static Future<void> recordAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_versionKey, LegalContent.currentLegalVersion);
    await prefs.setString(
        _timestampKey, DateTime.now().toUtc().toIso8601String());
  }

  /// The version the user last accepted, if any (for diagnostics/display).
  static Future<String?> acceptedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionKey);
  }
}
