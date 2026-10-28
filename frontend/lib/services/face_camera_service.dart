import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// 人脸取图失败。
class FaceCaptureException implements Exception {
  const FaceCaptureException(
    this.message, {
    this.cancelled = false,
    this.unavailable = false,
  });

  /// 可直接展示给老人的中文提示。
  final String message;

  /// 用户主动取消（例如点了取消按钮或返回键）。
  final bool cancelled;

  /// 当前设备没有原生实时相机能力，调用方可以回退系统拍照。
  final bool unavailable;

  @override
  String toString() => message;
}

/// 鸿蒙 A 版刷脸取图：调用原生实时相机（前置预览 + 圆框引导 + 自动抓拍）。
///
/// 其他平台（Android / iOS）没有实现该通道，[isAvailable] 会返回 false，
/// 调用方继续使用原来的系统拍照流程，互不影响。
class FaceCameraService {
  static const MethodChannel _channel =
      MethodChannel('smart_medicine_box/face_camera');

  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _captureTimeout = Duration(seconds: 60);

  static bool? _available;

  static bool get _osLooksLikeOhos {
    if (kIsWeb) return false;
    final os = Platform.operatingSystem.toLowerCase();
    return os == 'ohos' || os == 'openharmony' || os == 'harmonyos';
  }

  /// 原生实时相机是否可用。
  static Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final supported = await _channel
          .invokeMethod<bool>('isAvailable')
          .timeout(_probeTimeout);
      _available = supported ?? false;
    } on MissingPluginException {
      _available = false;
    } on TimeoutException {
      _available = false;
    } on PlatformException {
      _available = false;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// 打开原生实时相机并自动抓拍，返回 JPEG 字节。
  ///
  /// 返回 null 表示用户取消了刷脸。
  /// 抛出 [FaceCaptureException] 表示失败，调用方按提示处理。
  static Future<Uint8List?> capture({
    String mode = 'login',
    String hint = '请把脸放进圆框',
    Duration autoCaptureDelay = const Duration(milliseconds: 2000),
  }) async {
    try {
      final path = await _channel
          .invokeMethod<String>('capture', <String, dynamic>{
            'mode': mode,
            'hint': hint,
            'auto_capture_delay_ms': autoCaptureDelay.inMilliseconds,
          })
          .timeout(_captureTimeout);
      if (path == null || path.isEmpty) {
        throw const FaceCaptureException('没有拿到抓拍照片，请重试');
      }
      final file = File(path);
      final bytes = await file.readAsBytes();
      unawaited(_removeTempFile(file));
      if (bytes.isEmpty) {
        throw const FaceCaptureException('抓拍照片为空，请重试');
      }
      return bytes;
    } on MissingPluginException {
      _available = false;
      throw const FaceCaptureException(
        '当前设备不支持实时刷脸',
        unavailable: true,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELLED') return null;
      if (error.code == 'FACE_CAMERA_UNAVAILABLE') {
        _available = false;
        throw const FaceCaptureException(
          '实时刷脸暂时不可用',
          unavailable: true,
        );
      }
      throw FaceCaptureException(_messageOf(error));
    } on TimeoutException {
      throw const FaceCaptureException('刷脸超时，请重试');
    }
  }

  /// 人脸取图统一入口：原生实时相机优先，不可用时回退系统拍照。
  ///
  /// 返回 null 表示用户没有拍照或取消。
  static Future<Uint8List?> takeFacePhoto({
    required String mode,
    String hint = '请把脸放进圆框',
    Duration autoCaptureDelay = const Duration(milliseconds: 2000),
  }) async {
    if (!kIsWeb && await isAvailable()) {
      try {
        return await capture(
          mode: mode,
          hint: hint,
          autoCaptureDelay: autoCaptureDelay,
        );
      } on FaceCaptureException catch (error) {
        if (!error.unavailable) {
          rethrow;
        }
      }
    }
    if (kIsWeb) return null;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1080,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// 系统是否像鸿蒙（仅用于日志与提示，不影响回退逻辑）。
  static bool get runningOnOhos => _osLooksLikeOhos;

  static String _messageOf(PlatformException error) {
    final message = error.message?.trim();
    if (message == null || message.isEmpty) {
      return '刷脸失败，请重试或使用手机号验证码登录';
    }
    return message;
  }

  static Future<void> _removeTempFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 清理失败不影响业务。
    }
  }
}