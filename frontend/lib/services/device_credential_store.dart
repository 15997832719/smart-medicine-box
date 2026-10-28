import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceCredentialStore {
  static const MethodChannel _channel =
      MethodChannel('smart_medicine_box/secure_store');

  static const String _prefix = 'secure_';

  static Future<void> write(String key, String value) async {
    try {
      await _channel.invokeMethod<bool>('write', {'key': key, 'value': value});
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
      return;
    } on MissingPluginException {
      // Fall through to the legacy store on platforms without a native bridge.
    } on PlatformException {
      // Fall through so a device can still log in on older system versions.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }

  static Future<String?> read(String key) async {
    try {
      final value = await _channel.invokeMethod<String>('read', {'key': key});
      if (value != null) return value;
    } on MissingPluginException {
      // Fall through to the legacy store.
    } on PlatformException {
      // Fall through to the legacy store.
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  static Future<void> delete(String key) async {
    try {
      await _channel.invokeMethod<bool>('delete', {'key': key});
    } on MissingPluginException {
      // Ignore and clean the legacy store below.
    } on PlatformException {
      // Ignore and clean the legacy store below.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
