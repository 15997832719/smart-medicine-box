from pathlib import Path
base = Path(r'D:\smart-medicine-box')

def replace(path, old, new, expected=1):
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != expected:
        raise SystemExit(f'{path}: count={count}, expected={expected}: {old[:100]}')
    path.write_text(text.replace(old, new), encoding='utf-8')

model = base / 'frontend/lib/models/medicine.dart'
replace(model, "  final String remindTime;\n  final String? dose;\n  final bool isActive;", "  final String remindTime;\n  final DateTime? scheduleDate;\n  final String? dose;\n  final bool isActive;")
replace(model, "    required this.remindTime,\n    this.dose,", "    required this.remindTime,\n    this.scheduleDate,\n    this.dose,")
replace(model, "      remindTime: (json['remind_time'] ?? '08:00').toString(),\n      dose: _asString(json['dose']),", "      remindTime: (json['remind_time'] ?? '08:00').toString(),\n      scheduleDate: DateTime.tryParse('${json['schedule_date'] ?? ''}'),\n      dose: _asString(json['dose']),")

api = base / 'frontend/lib/services/api_service.dart'
replace(api, "  static Future<Schedule> createSchedule({\n    required int medicineId,\n    required String remindTime,\n    required String dose,\n    int? elderId,\n  }) async {\n    final body = {\n      'medicine_id': medicineId,\n      'title': '用药提醒',\n      'remind_time': remindTime,\n      'dose': dose,\n      'frequency': 'daily',\n      'enabled': true,\n    };", "  static Future<Schedule> createSchedule({\n    required int medicineId,\n    required String remindTime,\n    required String dose,\n    DateTime? scheduleDate,\n    int? elderId,\n  }) async {\n    final body = <String, dynamic>{\n      'medicine_id': medicineId,\n      'title': '用药提醒',\n      'remind_time': remindTime,\n      'dose': dose,\n      'frequency': scheduleDate == null ? 'daily' : 'once',\n      'enabled': true,\n      if (scheduleDate != null) 'schedule_date': _dateOnly(scheduleDate),\n    };")
replace(api, "  static Future<Schedule> updateSchedule({\n    required int scheduleId,\n    int? medicineId,\n    String? remindTime,\n    String? dose,\n    bool? isActive,\n    int? elderId,\n  }) async {\n    final body = <String, dynamic>{};\n    if (medicineId != null) body['medicine_id'] = medicineId;\n    if (remindTime != null) body['remind_time'] = remindTime;\n    if (dose != null) body['dose'] = dose;", "  static Future<Schedule> updateSchedule({\n    required int scheduleId,\n    int? medicineId,\n    String? remindTime,\n    String? dose,\n    DateTime? scheduleDate,\n    bool clearScheduleDate = false,\n    bool? isActive,\n    int? elderId,\n  }) async {\n    final body = <String, dynamic>{};\n    if (medicineId != null) body['medicine_id'] = medicineId;\n    if (remindTime != null) body['remind_time'] = remindTime;\n    if (dose != null) body['dose'] = dose;\n    if (clearScheduleDate) {\n      body['schedule_date'] = null;\n      body['frequency'] = 'daily';\n    } else if (scheduleDate != null) {\n      body['schedule_date'] = _dateOnly(scheduleDate);\n      body['frequency'] = 'once';\n    }")
# Add a local date formatter before _decode.
replace(api, "  static dynamic _decode(String body) {", "  static String _dateOnly(DateTime date) =>\n      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';\n\n  static dynamic _decode(String body) {")
print('schedule model/API patch applied')
