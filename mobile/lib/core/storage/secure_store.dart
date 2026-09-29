import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / Keystore-backed storage for identifiers that should not live in
/// plain SharedPreferences (e.g. the FCM device token registered per user).
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _deviceTokenKey(String uid) => 'fcm_token_$uid';

  Future<String?> registeredDeviceToken(String uid) =>
      _read(_deviceTokenKey(uid));

  Future<void> setRegisteredDeviceToken(String uid, String token) =>
      _write(_deviceTokenKey(uid), token);

  Future<void> clearRegisteredDeviceToken(String uid) =>
      _delete(_deviceTokenKey(uid));

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureStore read failed: $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStore write failed: $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureStore delete failed: $e');
    }
  }
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
