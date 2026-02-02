import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Service to manage persistent device identification.
/// Uses Keychain (iOS) / EncryptedSharedPreferences (Android) for persistence.
/// On iOS, data survives app reinstalls. On Android, it's cleared on reinstall.
class DeviceIdService {
  static const String _secureKey = 'shaka_device_id';
  static const String _legacyKey = 'shaka_device_id';
  static String? _cachedDeviceId;

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Get the device ID, creating one if it doesn't exist.
  /// Migrates from legacy shared_preferences to secure storage if needed.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      print('🆔 Using cached device ID: $_cachedDeviceId');
      return _cachedDeviceId!;
    }

    // Try secure storage first (persists through reinstalls on iOS)
    print('🆔 Reading device ID from secure storage...');
    String? deviceId = await _secureStorage.read(key: _secureKey);
    print('🆔 Secure storage returned: $deviceId');

    // Migrate from legacy shared_preferences if needed
    if (deviceId == null) {
      print('🆔 No secure storage ID, checking shared_preferences...');
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString(_legacyKey);
      print('🆔 SharedPreferences returned: $deviceId');
      if (deviceId != null) {
        // Migrate to secure storage
        await _secureStorage.write(key: _secureKey, value: deviceId);
        print('🆔 Migrated device ID to secure storage: $deviceId');
      }
    }

    // Generate new if neither exists
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _secureStorage.write(key: _secureKey, value: deviceId);
      print('🆔 Generated NEW device ID: $deviceId');
    }

    _cachedDeviceId = deviceId;
    print('🆔 Final device ID: $deviceId');
    return deviceId;
  }

  static void clearCache() {
    _cachedDeviceId = null;
  }
}
