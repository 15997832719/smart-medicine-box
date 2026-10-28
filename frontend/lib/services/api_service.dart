import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/auth_service.dart';
import '../core/config.dart';
import '../models/medicine.dart';
import '../models/speaker_binding.dart';

class ApiService {
  static AuthService? _auth;
  static final http.Client _mediaClient = http.Client();

  static void init(AuthService auth) {
    _auth = auth;
  }

  static Map<String, String> get _headers {
    final token = _auth?.token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Uri _uri(String path, {Map<String, String>? query}) =>
      ApiConfig.endpoint(path, query: query);

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static dynamic _decode(String body) {
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  static Iterable<String> _uniquePaths(List<String> paths) sync* {
    final seen = <String>{};
    for (final path in paths) {
      if (seen.add(path)) yield path;
    }
  }

  static Future<dynamic> _getFirst(List<String> paths, {Map<String, String>? query}) async {
    Object? lastError;
    for (final path in _uniquePaths(paths)) {
      try {
        final res = await http
            .get(_uri(path, query: query), headers: _headers)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
        lastError = 'HTTP ${res.statusCode}: ${res.body}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('请求失败：$lastError');
  }

  static Future<dynamic> _postFirst(
    List<String> paths,
    Map<String, dynamic> body, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    Object? lastError;
    for (final path in _uniquePaths(paths)) {
      try {
        final res = await http
            .post(
              _uri(path, query: query),
              headers: _headers,
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
        lastError = 'HTTP ${res.statusCode}: ${res.body}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('请求失败：$lastError');
  }

  static Future<Map<String, dynamic>> createSpeakerPairingCode() async {
    final data = await _postFirst([
      '${ApiConfig.apiPrefix}/speaker/pairing-code',
    ], const <String, dynamic>{});
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<List<SpeakerBindingInfo>> getSpeakerBindings() async {
    final data = await _getFirst(['${ApiConfig.apiPrefix}/speaker/bindings']);
    final list = data is List ? data : const [];
    return list
        .map((item) => SpeakerBindingInfo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  static Future<void> unbindSpeaker(int bindingId) async {
    final res = await http
        .delete(_uri('${ApiConfig.apiPrefix}/speaker/bindings/$bindingId'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(_errorMessage('解绑失败', res));
  }

  static Future<void> registerPushToken(
    String registrationId, {
    String platform = 'android',
  }) async {
    await _postFirst(
      [ApiConfig.pushToken],
      {'registration_id': registrationId, 'platform': platform},
    );
  }

  static Future<List<Medicine>> getMedicines({int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _getFirst([ApiConfig.medicines], query: query);
    return (data as List).map((e) => Medicine.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Medicine> addMedicine(Medicine med, {int? elderId}) async {
    final body = med.toJson();
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _postFirst([ApiConfig.medicines], body, query: query);
    return Medicine.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<Medicine> updateMedicine(Medicine med, {int? elderId}) async {
    final path = '${ApiConfig.medicines}/${med.id}';
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final res = await http.patch(
      _uri(path, query: query),
      headers: _headers,
      body: jsonEncode(med.toJson()),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Medicine.fromJson(Map<String, dynamic>.from(_decode(res.body)));
    }
    throw Exception(_errorMessage('修改药品失败', res));
  }

  static Future<void> deleteMedicine(int id, {int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    Object? lastError;
    for (final path in _uniquePaths(['${ApiConfig.medicines}/$id'])) {
      try {
        final res = await http
            .delete(_uri(path, query: query), headers: _headers)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        lastError = _errorMessage('删除药品失败', res);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError);
  }

  static Future<Map<String, dynamic>> aiRecognizeMedicine(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return aiRecognizeMedicineBytes(
      bytes,
      filename: imageFile.path.split(Platform.pathSeparator).last,
    );
  }

  static Future<Map<String, dynamic>> aiRecognizeMedicineBytes(
    List<int> bytes, {
    String filename = 'medicine.jpg',
  }) async {
    Object? lastError;
    for (final path in _uniquePaths([ApiConfig.aiRecognize])) {
      try {
        final req = http.MultipartRequest('POST', _uri(path));
        final token = _auth?.token;
        if (token != null) req.headers['Authorization'] = 'Bearer $token';
        req.files.add(
          http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: filename,
            contentType: MediaType('image', _imageSubtype(filename)),
          ),
        );
        final res = await req.send().timeout(const Duration(seconds: 45));
        final body = await res.stream.bytesToString();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return _normalizeAiResult(Map<String, dynamic>.from(_decode(body)));
        }
        lastError = 'HTTP ${res.statusCode}: $body';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('AI识别失败：$lastError');
  }

  static Map<String, dynamic> _normalizeAiResult(Map<String, dynamic> data) {
    final medicine = data['medicine'];
    if (medicine is Map) {
      final result = Map<String, dynamic>.from(medicine);
      result['confidence'] = data['confidence'];
      result['source'] = data['source'];
      result['spec'] ??= result['category'];
      result['valid_date'] ??= result['expire_date'];
      result['raw_response'] = jsonEncode(data);
      return result;
    }
    return data;
  }

  static String _imageSubtype(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpeg';
  }

  static Future<List<Medicine>> getExpiringMedicines({int days = 7, int? elderId}) async {
    final query = {'days': '$days', if (elderId != null) 'owner_id': '$elderId'};
    final data = await _getFirst([ApiConfig.expiring], query: query);
    final list = (data as List)
        .map((e) => Medicine.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final now = DateTime.now();
    return list
        .where(
          (medicine) =>
              medicine.you_xiao_ri_qi != null &&
              medicine.you_xiao_ri_qi!.difference(now).inDays <= days,
        )
        .toList();
  }

  static Future<List<MedicineAlert>> getAlerts({int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _getFirst([ApiConfig.alerts], query: query);
    return (data as List).map((e) => MedicineAlert.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Map<String, dynamic>> getAiStatus() async {
    final data = await _getFirst([ApiConfig.aiStatus]);
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Schedule>> getSchedules({int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _getFirst([ApiConfig.schedules], query: query);
    return (data as List).map((e) => Schedule.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Schedule> createSchedule({
    required int yao_pin_bian_hao,
    required String ti_xing_shi_jian,
    required String dose,
    DateTime? ji_hua_ri_qi,
    int? elderId,
  }) async {
    final body = <String, dynamic>{
      'medicine_id': yao_pin_bian_hao,
      'title': '用药提醒',
      'remind_time': ti_xing_shi_jian,
      'dose': dose,
      'frequency': ji_hua_ri_qi == null ? 'daily' : 'once',
      'enabled': true,
      if (ji_hua_ri_qi != null) 'schedule_date': _dateOnly(ji_hua_ri_qi),
    };
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _postFirst([ApiConfig.schedules], body, query: query);
    return Schedule.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<Schedule> updateSchedule({
    required int ji_hua_bian_hao,
    int? yao_pin_bian_hao,
    String? ti_xing_shi_jian,
    String? dose,
    DateTime? ji_hua_ri_qi,
    bool clearScheduleDate = false,
    bool? shi_fou_qi_yong,
    int? elderId,
  }) async {
    final body = <String, dynamic>{};
    if (yao_pin_bian_hao != null) body['medicine_id'] = yao_pin_bian_hao;
    if (ti_xing_shi_jian != null) body['remind_time'] = ti_xing_shi_jian;
    if (dose != null) body['dose'] = dose;
    if (clearScheduleDate) {
      body['schedule_date'] = null;
      body['frequency'] = 'daily';
    } else if (ji_hua_ri_qi != null) {
      body['schedule_date'] = _dateOnly(ji_hua_ri_qi);
      body['frequency'] = 'once';
    }
    if (shi_fou_qi_yong != null) {
      body['is_active'] = shi_fou_qi_yong;
      body['enabled'] = shi_fou_qi_yong;
    }
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final res = await http.patch(
      _uri('${ApiConfig.schedules}/$ji_hua_bian_hao', query: query),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Schedule.fromJson(Map<String, dynamic>.from(_decode(res.body)));
    }
    throw Exception(_errorMessage('修改计划失败', res));
  }

  static Future<void> deleteSchedule(int id, {int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    Object? lastError;
    for (final path in _uniquePaths(['${ApiConfig.schedules}/$id'])) {
      try {
        final res = await http
            .delete(_uri(path, query: query), headers: _headers)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        lastError = _errorMessage('删除计划失败', res);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError);
  }

  static Future<TodaySummary> getTodayLogs({int? elderId}) async {
    final query = elderId == null ? null : {'owner_id': '$elderId'};
    final data = await _getFirst([ApiConfig.logsToday], query: query);
    return TodaySummary.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<void> confirmMedication(int ji_hua_bian_hao, {String method = 'button'}) async {
    await _postFirst(
      [ApiConfig.logsConfirm],
      {'schedule_id': ji_hua_bian_hao, 'confirm_method': method},
    );
  }

  static Future<List<int>> synthesizeSpeech(String text) async {
    final res = await http
        .post(
          _uri('${ApiConfig.apiPrefix}/voice/synthesize'),
          headers: _headers,
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw Exception(_errorMessage('\u8bed\u97f3\u5408\u6210\u5931\u8d25', res));
  }

  static Future<String> transcribeVoice(File audioFile, {int? ownerId, String? traceId}) async {
    final bytes = await audioFile.readAsBytes();
    final filename = audioFile.path.split(Platform.pathSeparator).last;
    final query = <String, String>{
      if (ownerId != null) 'owner_id': '$ownerId',
      if (traceId != null) 'trace_id': traceId,
    };
    final req = http.MultipartRequest(
      'POST',
      _uri(ApiConfig.voiceTranscribe, query: query.isEmpty ? null : query),
    );
    final token = _auth?.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      http.MultipartFile.fromBytes(
        'audio',
        bytes,
        filename: filename.isEmpty ? 'voice.m4a' : filename,
      ),
    );

    try {
      final res = await req.send().timeout(const Duration(seconds: 120));
      final body = await res.stream.bytesToString();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = Map<String, dynamic>.from(_decode(body) as Map);
        final text = (data['text'] ?? '').toString().trim();
        if (text.isEmpty) throw Exception('语音识别没有返回文字');
        return text;
      }

      String detail = _voiceUploadError(res.statusCode);
      try {
        final data = _decode(body);
        if (data is Map && data['detail'] != null) {
          detail = data['detail'].toString();
        }
      } catch (_) {}
      throw Exception(detail.isEmpty ? 'HTTP ${res.statusCode}' : detail);
    } on TimeoutException {
      throw Exception('录音上传或识别超时，请检查网络后重试');
    } on SocketException {
      throw Exception('无法连接服务器，请检查网络');
    }
  }

  static String _voiceUploadError(int statusCode) {
    switch (statusCode) {
      case 401:
        return '登录已失效，请重新登录';
      case 413:
        return '录音文件过大，请缩短录音时间';
      case 503:
        return '语音转写服务暂不可用，请稍后重试';
      default:
        return '';
    }
  }

  static Future<Map<String, dynamic>> sendVoiceIntent(
    String text, {
    int? ji_hua_bian_hao,
    String? hui_hua_bian_hao,
    int? ownerId,
    String? traceId,
  }) async {
    final data = await _postFirst(
      [ApiConfig.logsVoiceIntent],
      {
        'text': text,
        if (ji_hua_bian_hao != null) 'schedule_id': ji_hua_bian_hao,
        if (hui_hua_bian_hao != null) 'session_id': hui_hua_bian_hao,
        if (ownerId != null) 'owner_id': ownerId,
        if (traceId != null) 'trace_id': traceId,
      },
      timeout: const Duration(seconds: 30),
    );
    final map = Map<String, dynamic>.from(data);
    if (map['reply'] != null && map['message'] == null) {
      map['message'] = map['reply'];
    }
    return map;
  }

  static Future<void> deleteAccount(String password) async {
    final res = await http.delete(
      _uri('${ApiConfig.apiPrefix}/auth/account'),
      headers: _headers,
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(_errorMessage('删除账号失败', res));
  }

  static Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    final data = await _postFirst([ApiConfig.smsSend], {'phone': phone});
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> smsLogin(String phone, String code) async {
    final data = await _postFirst([ApiConfig.smsLogin], {'phone': phone, 'code': code});
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> faceStatus() async {
    final data = await _getFirst([ApiConfig.faceStatus]);
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> deleteFace() async {
    final res = await http.delete(_uri(ApiConfig.faceEnroll), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(_errorMessage('删除人脸数据失败', res));
  }

  static Future<Map<String, dynamic>> recordFaceConsent() async {
    final data = await _postFirst([ApiConfig.faceConsent], {'version': 'v1'});
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> enrollFace(
    List<int> imageBytes, {
    required String deviceKey,
  }) async {
    final req = http.MultipartRequest('POST', _uri(ApiConfig.faceEnroll));
    final token = _auth?.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['device_key'] = deviceKey;
    if (imageBytes.isEmpty) throw Exception('拍摄的人脸图片为空，请重新拍摄');
    req.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'face.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );
    final res = await req.send().timeout(const Duration(seconds: 45));
    final body = await res.stream.bytesToString();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(body) as Map);
    }
    throw Exception(_errorMessageRaw('人脸录入失败', res.statusCode, body));
  }

  static Future<Map<String, dynamic>> faceLogin(
    List<int> imageBytes, {
    required String deviceKey,
  }) async {
    final req = http.MultipartRequest('POST', _uri(ApiConfig.faceLogin));
    req.fields['device_key'] = deviceKey;
    if (imageBytes.isEmpty) throw Exception('拍摄的人脸图片为空，请重新拍摄');
    req.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'face.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );
    final res = await req.send().timeout(const Duration(seconds: 45));
    final body = await res.stream.bytesToString();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(body) as Map);
    }
    throw Exception(_errorMessageRaw('刷脸登录失败', res.statusCode, body));
  }

  static Future<Map<String, dynamic>> enableDeviceCredential({
    String? deviceId,
    required String platform,
  }) async {
    final data = await _postFirst(
      [ApiConfig.deviceEnable],
      {if (deviceId != null) 'device_id': deviceId, 'platform': platform},
    );
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> loginWithDevice({
    required String deviceId,
    required String deviceSecret,
    required String platform,
  }) async {
    final res = await http
        .post(
          _uri(ApiConfig.deviceLogin),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'device_secret': deviceSecret,
            'platform': platform,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('设备快捷登录失败', res));
  }

  static Future<Map<String, dynamic>> startActivation() async {
    final data = await _postFirst([ApiConfig.activationStart], const <String, dynamic>{});
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> claimActivation({
    int? activationId,
    required String activationCode,
    required String nickname,
  }) async {
    final data = await _postFirst(
      [ApiConfig.activationClaim],
      {
        if (activationId != null) 'activation_id': activationId,
        'activation_code': activationCode,
        'nickname': nickname,
      },
    );
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>?> exchangeActivation({
    required int activationId,
    required String deviceSecret,
    required String platform,
  }) async {
    final res = await http
        .post(
          _uri(ApiConfig.activationExchange),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'activation_id': activationId,
            'device_secret': deviceSecret,
            'platform': platform,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 409) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('设备快捷登录失败', res));
  }

  static Future<List<Map<String, dynamic>>> getAuthDevices() async {
    final data = await _getFirst([ApiConfig.authDevices]);
    return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<void> revokeAuthDevice(int id) async {
    final res = await http.delete(_uri('${ApiConfig.authDevices}/$id'), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(_errorMessage('撤销设备失败', res));
  }

  static Future<void> revokeAllAuthDevices() async {
    final res = await http.delete(_uri(ApiConfig.authDevices), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception(_errorMessage('撤销全部设备失败', res));
  }

  static Future<List<Map<String, dynamic>>> getHardwareDevices() async {
    final data = await _getFirst([ApiConfig.hardwareDevices]);
    return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> createHardwareDevice({
    required String deviceUid,
    required String name,
    int? ownerId,
  }) async {
    final data = await _postFirst(
      [ApiConfig.hardwareDevices],
      {'device_uid': deviceUid, 'name': name, if (ownerId != null) 'owner_id': ownerId},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> createHardwareDeviceCommand({
    required int deviceId,
    required String commandType,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final data = await _postFirst(
      [ApiConfig.hardwareDeviceCommands(deviceId)],
      {'command_type': commandType, 'payload': payload},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> getHardwareDeviceCommand({
    required int deviceId,
    required int commandId,
  }) async {
    final data = await _getFirst([ApiConfig.hardwareDeviceCommand(deviceId, commandId)]);
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<List<Map<String, dynamic>>> getHardwareDeviceFaces(int deviceId) async {
    final data = await _getFirst([ApiConfig.hardwareDeviceFaces(deviceId)]);
    return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> updateHardwareFaceIdentity({
    required int deviceId,
    required int faceId,
    required String role,
    int? announceUserId,
  }) async {
    final res = await http
        .patch(
          _uri(ApiConfig.hardwareDeviceFace(deviceId, faceId)),
          headers: _headers,
          body: jsonEncode({
            'role': role,
            if (announceUserId != null) 'announce_user_id': announceUserId,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('设置人脸身份失败', res));
  }

  static Map<String, String> get authenticatedMediaHeaders {
    final token = _auth?.token;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Uri hardwareCameraAssetFileUri(int deviceId, int assetId) =>
      _uri(ApiConfig.hardwareDeviceCameraAssetFile(deviceId, assetId));

  static Uri hardwareCameraAssetThumbnailUri(int deviceId, int assetId) =>
      _uri(ApiConfig.hardwareDeviceCameraAssetThumbnail(deviceId, assetId));

  static Future<List<Map<String, dynamic>>> getHardwareCameraAssets(
    int deviceId, {
    String? kind,
    int limit = 50,
  }) async {
    final data = await _getFirst(
      [ApiConfig.hardwareDeviceCameraAssets(deviceId)],
      query: {'limit': '$limit', if (kind != null) 'kind': kind},
    );
    return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> reviewHardwareCameraAsset({
    required int deviceId,
    required int assetId,
    required String status,
    String? note,
  }) async {
    final res = await http
        .patch(
          _uri(ApiConfig.hardwareDeviceCameraAssetReview(deviceId, assetId)),
          headers: _headers,
          body: jsonEncode({
            'status': status,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('更新录像状态失败', res));
  }

  static Future<Map<String, dynamic>> startHardwareCameraPreview(int deviceId) async {
    final data = await _postFirst([
      ApiConfig.hardwareDeviceCameraPreviewStart(deviceId),
    ], const <String, dynamic>{});
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<void> stopHardwareCameraPreview(int deviceId) async {
    await _postFirst([
      ApiConfig.hardwareDeviceCameraPreviewStop(deviceId),
    ], const <String, dynamic>{});
  }

  static Future<Map<String, dynamic>> getHardwareCameraPreviewStatus(int deviceId) async {
    final data = await _getFirst([ApiConfig.hardwareDeviceCameraPreviewStatus(deviceId)]);
    return Map<String, dynamic>.from(data as Map);
  }

  static Uri hardwareCameraPreviewFrameUri(int deviceId) => _uri(
    ApiConfig.hardwareDeviceCameraPreviewFrame(deviceId),
    query: {'frame': '${DateTime.now().microsecondsSinceEpoch}'},
  );

  static Future<Uint8List> getHardwareCameraPreviewFrame(int deviceId) async {
    final uri = _uri(
      ApiConfig.hardwareDeviceCameraPreviewFrame(deviceId),
      query: {'frame': '${DateTime.now().microsecondsSinceEpoch}'},
    );
    final res = await _mediaClient
        .get(uri, headers: authenticatedMediaHeaders)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
      return res.bodyBytes;
    }
    throw Exception(_errorMessage('读取实时画面失败', res));
  }

  static Future<WebSocket> connectHardwareCameraPreviewSocket(int deviceId) async {
    final token = _auth?.token;
    if (token == null || token.isEmpty) {
      throw Exception('登录已失效，请重新登录');
    }
    final scheme = ApiConfig.baseUri.scheme == 'https' ? 'wss' : 'ws';
    final uri = ApiConfig.baseUri.replace(
      scheme: scheme,
      path: ApiConfig.hardwareDeviceCameraPreviewWs(deviceId),
    );
    return WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 8));
  }

  static Future<List<Map<String, dynamic>>> getHardwareRecognitionEvents(
    int deviceId, {
    int limit = 10,
  }) async {
    final data = await _getFirst(
      [ApiConfig.hardwareDeviceRecognitionEvents(deviceId)],
      query: {'limit': '$limit'},
    );
    return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> getHardwareRuntime(int deviceId) async {
    final data = await _getFirst([ApiConfig.hardwareDeviceRuntime(deviceId)]);
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> parseInstruction(String text) async {
    final data = await _postFirst([ApiConfig.parseInstruction], {'text': text});
    return Map<String, dynamic>.from(data);
  }

  static Future<List<MedicationLog>> getHistory(int elderId, {int days = 7}) async {
    final data = await _getFirst([ApiConfig.logsHistory(elderId)], query: {'days': '$days'});
    return (data as List).map((e) => MedicationLog.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final data = await _getFirst([ApiConfig.profile]);
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) async {
    final res = await http
        .patch(_uri(ApiConfig.profile), headers: _headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('保存资料失败', res));
  }

  static Future<Map<String, dynamic>> uploadProfileAvatar(
    Uint8List bytes, {
    String filename = 'avatar.jpg',
  }) async {
    if (bytes.isEmpty) throw Exception('头像图片为空');
    final req = http.MultipartRequest('POST', _uri(ApiConfig.profileAvatar));
    final token = _auth?.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: filename,
        contentType: MediaType('image', _imageSubtype(filename)),
      ),
    );
    final streamed = await req.send().timeout(const Duration(seconds: 35));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(body) as Map);
    }
    throw Exception(_errorMessageRaw('上传头像失败', streamed.statusCode, body));
  }

  static Future<Map<String, dynamic>> deleteProfileAvatar() async {
    final res = await http
        .delete(_uri(ApiConfig.profileAvatar), headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Map<String, dynamic>.from(_decode(res.body) as Map);
    }
    throw Exception(_errorMessage('恢复默认头像失败', res));
  }

  static Future<String> generateBindCode() async {
    final data = await _postFirst([ApiConfig.generateBindCode], {});
    return data['bind_code'];
  }

  static Future<void> bindFamily(String bindCode) async {
    await _postFirst([ApiConfig.bindFamily], {'bind_code': bindCode});
  }

  static Future<Map<String, dynamic>> getMyFamily() async {
    final data = await _getFirst([ApiConfig.myFamily]);
    return Map<String, dynamic>.from(data);
  }

  static String _errorMessageRaw(String fallback, int statusCode, String body) {
    try {
      final data = _decode(body);
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) return '$fallback：$detail';
      if (detail is Map) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return '$fallback：$message';
        final code = detail['code'];
        if (code is String && code.isNotEmpty) return '$fallback：$code';
      }
      if (detail != null) return '$fallback：$detail';
    } catch (_) {}
    return '$fallback：HTTP $statusCode';
  }

  static String _errorMessage(String fallback, http.Response res) {
    try {
      final data = _decode(res.body);
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) return '$fallback：$detail';
      if (detail is Map) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return '$fallback：$message';
      }
    } catch (_) {}
    return '$fallback：HTTP ${res.statusCode}';
  }
}
