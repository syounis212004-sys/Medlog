import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small wrapper around Android Keystore-backed storage. Every call is safe:
/// when the platform storage is not available (tests, unusual devices) reads
/// return null and writes return false, and the caller falls back.
class SecureKv {
  static const FlutterSecureStorage _s = FlutterSecureStorage();

  static Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> write(String key, String value) async {
    try {
      await _s.write(key: key, value: value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (_) {}
  }
}
