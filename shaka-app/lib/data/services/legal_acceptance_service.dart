import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/legal/legal_content.dart';
import 'device_id_service.dart';

/// Tracks acceptance of the current Terms/Privacy version.
///
/// The authoritative record lives server-side in the `legal_acceptances`
/// table (keyed to the anonymous device id). This service still keeps a local
/// `shared_preferences` mirror so the first-launch gate is instant and works
/// offline; if the server write fails (e.g. no signal at first launch) it is
/// queued and retried on the next launch via [syncPendingIfNeeded].
class LegalAcceptanceService {
  static const String _versionKey = 'legal_accepted_version';
  static const String _timestampKey = 'legal_accepted_at';
  static const String _pendingSyncKey = 'legal_pending_sync_version';

  // Acceptance endpoint lives under the /v1 API (the public legal *pages*
  // live at the root /legal path, which is different).
  static const String _endpoint =
      'https://shaka-production.up.railway.app/v1/legal/acceptances';

  /// True if the user has accepted the version currently in effect (local
  /// mirror — fast and offline-safe).
  static Future<bool> hasAcceptedCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionKey) == LegalContent.currentLegalVersion;
  }

  /// Records acceptance of the current version. Writes the local mirror first
  /// (so the gate passes immediately, even offline), then persists to the
  /// server; on failure the write is queued for retry.
  static Future<void> recordAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    const version = LegalContent.currentLegalVersion;

    await prefs.setString(_versionKey, version);
    await prefs.setString(
        _timestampKey, DateTime.now().toUtc().toIso8601String());

    final ok = await _postToServer(version);
    if (ok) {
      await prefs.remove(_pendingSyncKey);
    } else {
      await prefs.setString(_pendingSyncKey, version);
    }
  }

  /// Retries a previously-failed server write. Call once on app startup.
  static Future<void> syncPendingIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_pendingSyncKey);
    if (pending == null) return;
    if (await _postToServer(pending)) {
      await prefs.remove(_pendingSyncKey);
    }
  }

  static Future<bool> _postToServer(String version) async {
    try {
      final deviceId = await DeviceIdService.getDeviceId();
      final platform =
          Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-ID': deviceId,
            },
            body: jsonEncode({'legalVersion': version, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      // Offline / server error: caller queues a retry.
      return false;
    }
  }

  /// The version the user last accepted, if any (for diagnostics/display).
  static Future<String?> acceptedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_versionKey);
  }
}
