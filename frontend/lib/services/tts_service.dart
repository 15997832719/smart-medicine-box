import 'package:flutter/services.dart';

class TtsService {
  static const MethodChannel _channel =
      MethodChannel('smart_medicine_box/tts');

  static Future<bool> isNativeAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> playFile(String path) async {
    await _channel.invokeMethod<bool>('playFile', {'path': path});
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
