import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class VoiceCaptureException implements Exception {
  const VoiceCaptureException(this.message, {this.stage = 'capture'});

  final String message;
  final String stage;

  @override
  String toString() => message;
}

class VoiceCaptureService {
  static const MethodChannel _ohosChannel =
      MethodChannel('smart_medicine_box/voice_capture');

  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  bool _usingFallbackFormat = false;

  bool? _nativeOhos;

  bool get _osLooksLikeOhos {
    if (kIsWeb) return false;
    final os = Platform.operatingSystem.toLowerCase();
    return os == 'ohos' || os == 'openharmony' || os == 'harmonyos';
  }

  bool get _isOhos => _nativeOhos == true || _osLooksLikeOhos;

  Future<bool?> _probeOhosPermission() async {
    try {
      final result = await _ohosChannel
          .invokeMethod<bool>('hasMicrophonePermission')
          .timeout(const Duration(seconds: 5));
      if (result != null) {
        _nativeOhos = true;
        return result;
      }
    } on MissingPluginException {
      _nativeOhos = false;
    } on TimeoutException {
      _nativeOhos = false;
    } on PlatformException {
      _nativeOhos = false;
    } catch (_) {
      _nativeOhos = false;
    }
    return null;
  }

  Future<bool> hasPermission() async {
    final nativeResult = await _probeOhosPermission();
    if (nativeResult != null) return nativeResult;
    if (_osLooksLikeOhos) return false;
    return _recorder.hasPermission();
  }

  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    if (_nativeOhos == true || _osLooksLikeOhos) {
      try {
        final granted = await _ohosChannel
            .invokeMethod<bool>('requestMicrophonePermission')
            .timeout(const Duration(seconds: 15));
        if (granted != null) {
          _nativeOhos = true;
          return granted;
        }
      } on MissingPluginException {
        _nativeOhos = false;
      } on TimeoutException {
        return false;
      } on PlatformException {
        return false;
      } catch (_) {
        return false;
      }
    }
    if (kIsWeb || _osLooksLikeOhos) return false;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String> start() async {
    if (_recordingPath != null) {
      throw const VoiceCaptureException(
        '当前已在录音，请先停止录音',
        stage: 'start',
      );
    }
    if (!await requestPermission()) {
      throw const VoiceCaptureException(
        '麦克风权限不可用，请在系统设置中开启',
        stage: 'permission',
      );
    }

    if (_isOhos) {
      final path = await _ohosChannel
          .invokeMethod<String>('startRecording')
          .timeout(const Duration(seconds: 10));
      if (path == null || path.isEmpty) {
        throw const VoiceCaptureException(
          '鸿蒙录音启动失败',
          stage: 'start',
        );
      }
      _recordingPath = path;
      return path;
    }

    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final primaryPath =
        '${directory.path}${Platform.pathSeparator}voice_$stamp.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: primaryPath,
      );
      _recordingPath = primaryPath;
      _usingFallbackFormat = false;
      return primaryPath;
    } catch (_) {
      final fallbackPath =
          '${directory.path}${Platform.pathSeparator}voice_$stamp.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: fallbackPath,
      );
      _recordingPath = fallbackPath;
      _usingFallbackFormat = true;
      return fallbackPath;
    }
  }

  Future<String> stop() async {
    final expectedPath = _recordingPath;
    if (expectedPath == null) {
      throw const VoiceCaptureException(
        '当前没有正在进行的录音',
        stage: 'stop',
      );
    }

    try {
      final path = _isOhos
          ? await _ohosChannel
              .invokeMethod<String>('stopRecording')
              .timeout(const Duration(seconds: 10))
          : await _recorder.stop();
      final resolvedPath = (path == null || path.isEmpty) ? expectedPath : path;
      final file = File(resolvedPath);
      if (!await file.exists()) {
        throw const VoiceCaptureException(
          '没有生成录音文件',
          stage: 'file',
        );
      }
      if (await file.length() <= 2048) {
        throw const VoiceCaptureException(
          '录音太短或没有录到声音，请重试',
          stage: 'file',
        );
      }
      return resolvedPath;
    } finally {
      _recordingPath = null;
      _usingFallbackFormat = false;
    }
  }

  bool get usesFallbackFormat => _usingFallbackFormat;

  Future<void> dispose() async {
    try {
      if (_recordingPath != null) {
        if (_isOhos) {
          await _ohosChannel.invokeMethod<void>('cancelRecording');
        } else {
          await _recorder.stop();
        }
      }
    } catch (_) {
      // Cleanup must not hide the original capture error.
    }
    if (!_isOhos) {
      await _recorder.dispose();
    }
    _recordingPath = null;
  }
}
