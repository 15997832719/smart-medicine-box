import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'config.dart';

class User {
  final int id;
  final String phone;
  final String? nickname;
  final String role;
  final String? token;

  User({
    required this.id,
    required this.phone,
    this.nickname,
    required this.role,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _asInt(json['id'], fallback: 1),
      phone: (json['phone'] ?? '').toString(),
      nickname: json['nickname']?.toString(),
      role: (json['role'] ?? 'elder').toString(),
      token: json['token']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'nickname': nickname,
        'role': role,
        'token': token,
      };
}

class AuthService extends ChangeNotifier {
  User? _currentUser;
  String? _token;
  bool _isLoading = true;
  String? _lastError;

  User? get dang_qian_yong_hu => _currentUser;
  String? get token => _token;
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
      final userJson = prefs.getString('user');
      if (_token == null || _token!.startsWith('demo-token')) {
        _token = null;
        await prefs.remove('access_token');
        await prefs.remove('user');
      } else if (userJson != null) {
        _currentUser = User.fromJson(Map<String, dynamic>.from(jsonDecode(userJson)));
      }
    } finally {
      _isLoading = false;
      ApiService.init(this);
      notifyListeners();
    }
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
        _currentUser = data['user'] is Map<String, dynamic>
            ? User.fromJson(data['user'])
            : null;
        await _saveToken();
        _finishAuth();
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
        _currentUser = data['user'] is Map<String, dynamic>
            ? User.fromJson(data['user'])
            : null;
        await _saveToken();
        _finishAuth();
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

  Future<void> _saveToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString('access_token', _token!);
    if (_currentUser != null) {
      await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    }
  }

  Future<void> logout() async {
    try {
      await NotificationService.instance.qing_chu_yong_yao_ji_hua();
    } catch (_) {
      
    }
    _token = null;
    _currentUser = null;
    ApiService.init(this);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user');
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
