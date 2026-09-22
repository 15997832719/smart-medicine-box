from pathlib import Path
import re

base = Path(r'D:\smart-medicine-box')

backend_files = list((base / 'backend/app').glob('*.py')) + list((base / 'backend/tests').glob('*.py'))
frontend_files = list((base / 'frontend/lib').rglob('*.dart')) + list((base / 'frontend/test').rglob('*.dart'))

backend_renames = {
    'hash_password': 'sheng_cheng_mi_ma_zhai_yao',
    'verify_password': 'jiao_yan_mi_ma_zhai_yao',
    '_b64encode': '_bian_ma_base64',
    '_b64decode': '_jie_ma_base64',
    '_create_token': '_sheng_cheng_ling_pai',
    '_decode_token': '_jie_xi_ling_pai',
    'user_to_read': 'yong_hu_zhuan_du_qu',
    'tags_to_string': 'biao_qian_zhuan_zi_fu_chuan',
    'string_to_tags': 'zi_fu_chuan_zhuan_biao_qian',
    'to_medicine_read': 'yao_pin_zhuan_du_qu',
    'build_medicine': 'gou_jian_yao_pin',
    'list_alerts': 'lie_chu_jing_gao',
    'normalize_voice_text': 'gui_fan_hua_yu_yin_wen_ben',
    'detect_voice_intent': 'shi_bie_yu_yin_yi_tu',
    '_parse_model_date': '_jie_xi_mo_xing_ri_qi',
    'normalized': 'gui_fan_hua_wen_ben',
}

frontend_renames = {
    'currentUserId': 'dang_qian_yong_hu_bian_hao',
    'currentUser': 'dang_qian_yong_hu',
    'accessToken': 'fang_wen_ling_pai',
    'registerCurrentDevice': 'zhu_ce_dang_qian_she_bei',
    'clearMedicationSchedules': 'qing_chu_yong_yao_ji_hua',
    'scheduleMedication': 'an_pai_yong_yao_ti_xing',
    'medicineName': 'yao_pin_ming_cheng',
    'medicineId': 'yao_pin_bian_hao',
    'scheduleDate': 'ji_hua_ri_qi',
    'scheduleId': 'ji_hua_bian_hao',
    'plannedAt': 'ji_hua_shi_jian',
    'validDate': 'you_xiao_ri_qi',
    'userId': 'yong_hu_bian_hao',
    'remindTime': 'ti_xing_shi_jian',
    'isActive': 'shi_fou_qi_yong',
    '_selectedMedicine': '_xuan_zhong_yao_pin',
    '_medicines': '_yao_pin_lie_biao',
    '_schedules': '_yong_yao_ji_hua_lie_biao',
    '_alerts': '_jing_gao_lie_biao',
    '_loading': '_jia_zai_zhong',
    '_saving': '_bao_cun_zhong',
    '_error': '_cuo_wu',
    '_tab': '_dang_qian_biao_qian',
    '_doseController': '_ji_liang_kong_zhi_qi',
    '_quickDoses': '_kuai_su_ji_liang',
}

def rename_files(files, mapping):
    for path in files:
        text = path.read_text(encoding='utf-8')
        updated = text
        for old, new in mapping.items():
            updated = re.sub(r'\b' + re.escape(old) + r'\b', new, updated)
        if updated != text:
            path.write_text(updated, encoding='utf-8')

rename_files(backend_files, backend_renames)
rename_files(frontend_files, frontend_renames)

# seed_demo_data is both a settings field and a function name. Rename only the function and its call.
main_path = base / 'backend/app/main.py'
main = main_path.read_text(encoding='utf-8')
main = main.replace('def seed_demo_data() -> None:', 'def chu_shi_hua_yan_shi_shu_ju() -> None:', 1)
main = main.replace('    seed_demo_data()\n', '    chu_shi_hua_yan_shi_shu_ju()\n', 1)
main = main.replace('settings = get_settings()\n', 'settings = get_settings()\nAPI_PREFIX = settings.api_prefix\n', 1)
main = main.replace('prefix=settings.api_prefix', 'prefix=API_PREFIX')
main_path.write_text(main, encoding='utf-8')

# Global endpoint builder in ApiConfig.
config_path = base / 'frontend/lib/core/config.dart'
config = config_path.read_text(encoding='utf-8')
anchor = "  static const String apiPrefix = '/api/v1';\n"
addition = anchor + "\n  static final Uri baseUri = Uri.parse(baseUrl);\n\n  static Uri endpoint(String path, {Map<String, String>? query}) {\n    final uri = baseUri.replace(path: path);\n    if (query == null || query.isEmpty) return uri;\n    return uri.replace(queryParameters: {...uri.queryParameters, ...query});\n  }\n"
if config.count(anchor) != 1:
    raise SystemExit('ApiConfig anchor count mismatch')
config = config.replace(anchor, addition, 1)
config_path.write_text(config, encoding='utf-8')

# Replace local auth URI construction with the global endpoint helper.
auth_path = base / 'frontend/lib/core/auth_service.dart'
auth = auth_path.read_text(encoding='utf-8')
auth = auth.replace("Uri.parse('${ApiConfig.baseUrl}${ApiConfig.login}')", 'ApiConfig.endpoint(ApiConfig.login)')
auth = auth.replace("Uri.parse('${ApiConfig.baseUrl}${ApiConfig.register}')", 'ApiConfig.endpoint(ApiConfig.register)')
auth_path.write_text(auth, encoding='utf-8')

# Use the global endpoint helper in ApiService.
api_path = base / 'frontend/lib/services/api_service.dart'
api = api_path.read_text(encoding='utf-8')
old = "  static Uri _uri(String path, {Map<String, String>? query}) {\n    final uri = Uri.parse('${ApiConfig.baseUrl}$path');\n    if (query == null || query.isEmpty) return uri;\n    return uri.replace(queryParameters: {...uri.queryParameters, ...query});\n  }\n"
new = "  static Uri _uri(String path, {Map<String, String>? query}) =>\n      ApiConfig.endpoint(path, query: query);\n"
if api.count(old) != 1:
    raise SystemExit(f'ApiService uri block count={api.count(old)}')
api_path.write_text(api.replace(old, new, 1), encoding='utf-8')

print('conservative pinyin/global refactor applied')
