import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/auth_service.dart';
import '../core/config.dart';
import '../models/medicine.dart';
import '../models/speaker_binding.dart';

class ApiService {
  static AuthService? _auth;

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
        final res = await http.get(_uri(path, query: query), headers: _headers).timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
        lastError = 'HTTP ${res.statusCode}: ${res.body}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('请求失败：$lastError');
  }

  static Future<dynamic> _postFirst(List<String> paths, Map<String, dynamic> body, {Map<String, String>? query}) async {
    Object? lastError;
    for (final path in _uniquePaths(paths)) {
      try {
        final res = await http
            .post(_uri(path, query: query), headers: _headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
        lastError = 'HTTP ${res.statusCode}: ${res.body}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('请求失败：$lastError');
  }

  
  static Future<Map<String, dynamic>> createSpeakerPairingCode() async {
    final data = await _postFirst(['${ApiConfig.apiPrefix}/speaker/pairing-code'], const <String, dynamic>{});
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

  static Future<void> registerPushToken(String registrationId, {String platform = 'android'}) async {
    await _postFirst([ApiConfig.pushToken], {'registration_id': registrationId, 'platform': platform});
  }

  static Future<List<Medicine>> getMedicines({int? elderId}) async {
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    final data = await _getFirst([ApiConfig.medicines], query: query);
    return (data as List).map((e) => Medicine.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Medicine> addMedicine(Medicine med, {int? elderId}) async {
    final body = med.toJson();
    if (elderId != null) body['elder_id'] = elderId;
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    final data = await _postFirst([ApiConfig.medicines], body, query: query);
    return Medicine.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<Medicine> updateMedicine(Medicine med, {int? elderId}) async {
    final path = '${ApiConfig.medicines}/${med.id}';
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    final res = await http.patch(_uri(path, query: query), headers: _headers, body: jsonEncode(med.toJson()));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Medicine.fromJson(Map<String, dynamic>.from(_decode(res.body)));
    }
    throw Exception(_errorMessage('修改药品失败', res));
  }

  static Future<void> deleteMedicine(int id, {int? elderId}) async {
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    Object? lastError;
    for (final path in _uniquePaths(['${ApiConfig.medicines}/$id'])) {
      try {
        final res = await http.delete(_uri(path, query: query), headers: _headers).timeout(const Duration(seconds: 8));
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
    return aiRecognizeMedicineBytes(bytes, filename: imageFile.path.split(Platform.pathSeparator).last);
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
        req.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: filename,
          contentType: MediaType('image', _imageSubtype(filename)),
        ));
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
    final query = {'days': '$days', if (elderId != null) 'elder_id': '$elderId'};
    final data = await _getFirst([ApiConfig.expiring], query: query);
    final list = (data as List).map((e) => Medicine.fromJson(Map<String, dynamic>.from(e))).toList();
    final now = DateTime.now();
    return list.where((medicine) => medicine.you_xiao_ri_qi != null && medicine.you_xiao_ri_qi!.difference(now).inDays <= days).toList();
  }

  static Future<List<MedicineAlert>> getAlerts({int? elderId}) async {
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    final data = await _getFirst([ApiConfig.alerts], query: query);
    return (data as List).map((e) => MedicineAlert.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<Map<String, dynamic>> getAiStatus() async {
    final data = await _getFirst([ApiConfig.aiStatus]);
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Schedule>> getSchedules({int? elderId}) async {
    final query = elderId == null ? null : {'elder_id': '$elderId'};
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
    if (elderId != null) body['elder_id'] = elderId;
    final query = elderId == null ? null : {'elder_id': '$elderId'};
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
    final query = elderId == null ? null : {'elder_id': '$elderId'};
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
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    Object? lastError;
    for (final path in _uniquePaths(['${ApiConfig.schedules}/$id'])) {
      try {
        final res = await http.delete(_uri(path, query: query), headers: _headers).timeout(const Duration(seconds: 8));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        lastError = _errorMessage('删除计划失败', res);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError);
  }

  static Future<TodaySummary> getTodayLogs({int? elderId}) async {
    final query = elderId == null ? null : {'elder_id': '$elderId'};
    final data = await _getFirst([ApiConfig.logsToday], query: query);
    return TodaySummary.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<void> confirmMedication(int ji_hua_bian_hao, {String method = 'button'}) async {
    await _postFirst([ApiConfig.logsConfirm], {
      'schedule_id': ji_hua_bian_hao,
      'confirm_method': method,
    });
  }

  static Future<String> transcribeVoice(File audioFile) async {
    final bytes = await audioFile.readAsBytes();
    final filename = audioFile.path.split(Platform.pathSeparator).last;
    final req = http.MultipartRequest('POST', _uri(ApiConfig.voiceTranscribe));
    final token = _auth?.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes(
      'audio',
      bytes,
      filename: filename.isEmpty ? 'voice.m4a' : filename,
    ));

    final res = await req.send().timeout(const Duration(seconds: 120));
    final body = await res.stream.bytesToString();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = Map<String, dynamic>.from(_decode(body) as Map);
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) throw Exception('语音识别没有返回文字');
      return text;
    }

    String detail = 'HTTP ${res.statusCode}';
    try {
      final data = _decode(body);
      if (data is Map && data['detail'] != null) detail = data['detail'].toString();
    } catch (_) {}
    throw Exception('语音识别失败：$detail');
  }
  static Future<Map<String, dynamic>> sendVoiceIntent(String text, {int? ji_hua_bian_hao}) async {
    final data = await _postFirst([ApiConfig.logsVoiceIntent], {
      'text': text,
      if (ji_hua_bian_hao != null) 'schedule_id': ji_hua_bian_hao,
    });
    final map = Map<String, dynamic>.from(data);
    if (map['reply'] != null && map['message'] == null) {
      map['message'] = map['reply'];
    }
    return map;
  }

  static Future<Map<String, dynamic>> parseInstruction(String text) async {
    final data = await _postFirst([ApiConfig.parseInstruction], {'text': text});
    return Map<String, dynamic>.from(data);
  }

  static Future<List<MedicationLog>> getHistory(int elderId, {int days = 7}) async {
    final data = await _getFirst([ApiConfig.logsHistory(elderId)], query: {'days': '$days'});
    return (data as List).map((e) => MedicationLog.fromJson(Map<String, dynamic>.from(e))).toList();
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

  static String _errorMessage(String fallback, http.Response res) {
    try {
      final data = _decode(res.body);
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) return '$fallback：$detail';
    } catch (_) {}
    return '$fallback：HTTP ${res.statusCode}';
  }
}
