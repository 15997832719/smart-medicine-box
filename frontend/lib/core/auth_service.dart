import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/device_credential_store.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'config.dart';

class User {
  final int id;
  final String phone;
  final String? nickname;
  final String role;
  final String? token;
  final String? avatarUrl;
  final String? gender;
  final DateTime? birthDate;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? allergyNotes;

  User({
    required this.id,
    required this.phone,
    this.nickname,
    required this.role,
    this.token,
    this.avatarUrl,
    this.gender,
    this.birthDate,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.allergyNotes,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _asInt(json['id'], fallback: 1),
      phone: (json['phone'] ?? '').toString(),
      nickname: json['nickname']?.toString(),
      role: (json['role'] ?? 'elder').toString(),
      token: json['token']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      gender: json['gender']?.toString(),
      birthDate: DateTime.tryParse(json['birth_date']?.toString() ?? ''),
      emergencyContactName: json['emergency_contact_name']?.toString(),
      emergencyContactPhone: json['emergency_contact_phone']?.toString(),
      allergyNotes: json['allergy_notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'nickname': nickname,
    'role': role,
    'token': token,
    'avatar_url': avatarUrl,
    'gender': gender,
    'birth_date': birthDate == null
        ? null
        : '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}',
    'emergency_contact_name': emergencyContactName,
    'emergency_contact_phone': emergencyContactPhone,
    'allergy_notes': allergyNotes,
  };
}

class AuthService extends ChangeNotifier {
  User? _currentUser;
  String? _token;
  String? _deviceId;
  bool _isLoading = true;
  String? _lastError;

  User? get dang_qian_yong_hu => _currentUser;
  String? get token => _token;
  String? get deviceId => _deviceId;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null;
  String? get lastError => _lastError;

  AuthService() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('access_token');
      _deviceId = await DeviceCredentialStore.read('device_id');
      final userJson = prefs.getString('user');
      if (_token == null || _token!.startsWith('demo-token')) {
        _token = null;
        _currentUser = null;
        await prefs.remove('access_token');
        await prefs.remove('user');
        final deviceSecret = await DeviceCredentialStore.read('device_secret');
        if (_deviceId != null && deviceSecret != null && deviceSecret.isNotEmpty) {
          await _exchangeStoredDevice(
            deviceId: _deviceId!,
            deviceSecret: deviceSecret,
            platform:
                await DeviceCredentialStore.read('device_platform') ?? Platform.operatingSystem,
            notify: false,
          );
        } else {
          final activationId = int.tryParse(
            await DeviceCredentialStore.read('activation_id') ?? '',
          );
          final legacySecret = await DeviceCredentialStore.read('device_secret');
          if (activationId != null && legacySecret != null && legacySecret.isNotEmpty) {
            await _exchangeActivationCredential(
              activationId: activationId,
              deviceSecret: legacySecret,
              platform: Platform.operatingSystem,
              notify: false,
            );
          }
        }
      } else if (userJson != null) {
        _currentUser = User.fromJson(Map<String, dynamic>.from(jsonDecode(userJson)));
      }
    } finally {
      _isLoading = false;
      ApiService.init(this);
      notifyListeners();
    }
  }

  Future<bool> hasStoredDeviceCredentials() async {
    final deviceId = await DeviceCredentialStore.read('device_id');
    final deviceSecret = await DeviceCredentialStore.read('device_secret');
    return deviceId != null && deviceSecret != null && deviceSecret.isNotEmpty;
  }

  Future<bool> _exchangeStoredDevice({
    required String deviceId,
    required String deviceSecret,
    required String platform,
    bool notify = true,
  }) async {
    try {
      final data = await ApiService.loginWithDevice(
        deviceId: deviceId,
        deviceSecret: deviceSecret,
        platform: platform,
      );
      return await _acceptSession(data, notify: notify);
    } catch (error) {
      _lastError = '设备快捷登录失败：$error';
      return false;
    }
  }

  Future<bool> _exchangeActivationCredential({
    required int activationId,
    required String deviceSecret,
    required String platform,
    bool notify = true,
  }) async {
    try {
      final res = await http
          .post(
            ApiConfig.endpoint(ApiConfig.activationExchange),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'activation_id': activationId,
              'device_secret': deviceSecret,
              'platform': platform,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lastError = _extractErrorMessage(res.body);
        return false;
      }
      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      await DeviceCredentialStore.write('device_id', '${data['device_id']}');
      await DeviceCredentialStore.write('device_secret', deviceSecret);
      await DeviceCredentialStore.write('device_platform', platform);
      return await _acceptSession(data, notify: notify);
    } catch (error) {
      _lastError = '设备快捷登录失败：$error';
      return false;
    }
  }

  Future<bool> _acceptSession(Map<String, dynamic> data, {required bool notify}) async {
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty || data['user'] is! Map) {
      _lastError = '设备登录响应无效';
      return false;
    }
    _token = token;
    _deviceId = data['device_id']?.toString() ?? _deviceId;
    _currentUser = User.fromJson(Map<String, dynamic>.from(data['user']));
    await _saveToken();
    if (notify) _finishAuth();
    return true;
  }

  Future<void> _enableDeviceCredential() async {
    if (_token == null) return;
    try {
      final data = await ApiService.enableDeviceCredential(
        deviceId: _deviceId,
        platform: Platform.operatingSystem,
      );
      final deviceId = data['device_id']?.toString();
      final deviceSecret = data['device_secret']?.toString();
      if (deviceId == null || deviceSecret == null || deviceSecret.isEmpty) return;
      _deviceId = deviceId;
      await DeviceCredentialStore.write('device_id', deviceId);
      await DeviceCredentialStore.write('device_secret', deviceSecret);
      await DeviceCredentialStore.write('device_platform', Platform.operatingSystem);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_id', deviceId);
    } catch (_) {
      // Login must remain successful even when biometric enrollment is unavailable.
    }
  }

  Future<String> getDeviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('face_device_key');
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final key = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('face_device_key', key);
    return key;
  }

  Future<bool> acceptFaceLogin(Map<String, dynamic> data) async {
    return _acceptSession(data, notify: true);
  }

  Future<bool> acceptSmsLogin(Map<String, dynamic> data) async {
    return _acceptSession(data, notify: true);
  }

  Future<bool> acceptDeviceLogin(
    Map<String, dynamic> data, {
    required int activationId,
    required String deviceSecret,
    required String platform,
  }) async {
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty || data['user'] is! Map) {
      _lastError = '设备登录响应无效';
      return false;
    }
    _token = token;
    _currentUser = User.fromJson(Map<String, dynamic>.from(data['user']));
    _deviceId = data['device_id']?.toString();
    if (_deviceId != null) {
      await DeviceCredentialStore.write('device_id', _deviceId!);
    }
    await DeviceCredentialStore.write('device_secret', deviceSecret);
    await DeviceCredentialStore.write('device_platform', platform);
    await _saveToken();
    _finishAuth();
    return true;
  }

  Future<bool> tryStoredDeviceLogin() async {
    final deviceId = await DeviceCredentialStore.read('device_id');
    final deviceSecret = await DeviceCredentialStore.read('device_secret');
    if (deviceId == null || deviceSecret == null || deviceSecret.isEmpty) {
      return false;
    }
    _isLoading = true;
    notifyListeners();
    final ok = await _exchangeStoredDevice(
      deviceId: deviceId,
      deviceSecret: deviceSecret,
      platform: await DeviceCredentialStore.read('device_platform') ?? Platform.operatingSystem,
    );
    if (!ok) _finishAuth();
    return ok;
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final res = await http
          .post(
            ApiConfig.endpoint(ApiConfig.login),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password}),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body));
        final fang_wen_ling_pai = data['access_token']?.toString();
        if (fang_wen_ling_pai == null || fang_wen_ling_pai.isEmpty || data['user'] is! Map) {
          _lastError = '登录响应缺少有效账号信息';
          _finishAuth();
          return false;
        }
        _token = fang_wen_ling_pai;
        _currentUser = data['user'] is Map<String, dynamic> ? User.fromJson(data['user']) : null;
        await _saveToken();
        _finishAuth();
        await _enableDeviceCredential();
        return true;
      }

      _lastError = _extractErrorMessage(res.body);
    } catch (error) {
      _lastError = '无法连接服务器，请检查网络后重试：$error';
    }

    _finishAuth();
    return false;
  }

  Future<bool> register({
    required String phone,
    required String password,
    required String role,
    String? nickname,
  }) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final res = await http
          .post(
            ApiConfig.endpoint(ApiConfig.register),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'password': password,
              'role': role,
              'nickname': nickname,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body));
        final fang_wen_ling_pai = data['access_token']?.toString();
        if (fang_wen_ling_pai == null || fang_wen_ling_pai.isEmpty || data['user'] is! Map) {
          _lastError = '注册响应缺少有效账号信息';
          _finishAuth();
          return false;
        }
        _token = fang_wen_ling_pai;
        _currentUser = data['user'] is Map<String, dynamic> ? User.fromJson(data['user']) : null;
        await _saveToken();
        _finishAuth();
        await _enableDeviceCredential();
        return true;
      }

      _lastError = _extractErrorMessage(res.body);
    } catch (error) {
      _lastError = '无法连接服务器，请检查网络后重试：$error';
    }

    _finishAuth();
    return false;
  }

  void _finishAuth() {
    _isLoading = false;
    ApiService.init(this);
    notifyListeners();
    if (_token != null) {
      PushService.instance.zhu_ce_dang_qian_she_bei().catchError((_) {});
    }
  }

  Future<void> applyProfile(Map<String, dynamic> profile) async {
    if (_currentUser == null) return;
    _currentUser = User.fromJson({
      ..._currentUser!.toJson(),
      ...profile,
      'token': _currentUser!.token,
    });
    await _saveToken();
    notifyListeners();
  }

  Future<void> _saveToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString('access_token', _token!);
    if (_currentUser != null) {
      await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    }
    if (_deviceId != null) await prefs.setString('device_id', _deviceId!);
  }

  Future<void> logout() async {
    try {
      await NotificationService.instance.qing_chu_yong_yao_ji_hua();
    } catch (_) {}
    _token = null;
    _deviceId = null;
    _currentUser = null;
    ApiService.init(this);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user');
    await DeviceCredentialStore.delete('activation_id');
    await DeviceCredentialStore.delete('device_secret');
    await DeviceCredentialStore.delete('device_platform');
    await prefs.remove('device_id');
    notifyListeners();
  }

  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String _extractErrorMessage(String body) {
    try {
      final data = jsonDecode(body);
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) return '填写信息格式不正确';
    } catch (_) {}
    return '请求失败，请稍后重试';
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
