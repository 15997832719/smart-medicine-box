class Medicine {
  final int id;
  final int yong_hu_bian_hao;
  final String name;
  final String? spec;
  final String? category;
  final String? manufacturer;
  final String? description;
  final String? dosage;
  final String? frequency;
  final String? precautions;
  final List<String> conflictTags;
  final int stockCount;
  final int lowStockThreshold;
  final DateTime? you_xiao_ri_qi;
  final String? imageUrl;
  final String? aiResult;
  final DateTime createdAt;

  Medicine({
    required this.id,
    required this.yong_hu_bian_hao,
    required this.name,
    this.spec,
    this.category,
    this.manufacturer,
    this.description,
    this.dosage,
    this.frequency,
    this.precautions,
    this.conflictTags = const [],
    this.stockCount = 0,
    this.lowStockThreshold = 3,
    this.you_xiao_ri_qi,
    this.imageUrl,
    this.aiResult,
    required this.createdAt,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final conflictRaw = json['conflict_tags'];
    final validDateRaw = json['valid_date'] ?? json['expire_date'];
    final createdAtRaw = json['created_at'];
    return Medicine(
      id: _asInt(json['id']),
      yong_hu_bian_hao: _asInt(json['user_id']),
      name: (json['name'] ?? '未知药品').toString(),
      spec: _asString(json['spec']),
      category: _asString(json['category']),
      manufacturer: _asString(json['manufacturer']),
      description: _asString(json['description']),
      dosage: _asString(json['dosage']),
      frequency: _asString(json['frequency']),
      precautions: _asString(json['precautions']),
      conflictTags: conflictRaw is List ? conflictRaw.map((e) => e.toString()).toList() : const [],
      stockCount: _asInt(json['stock_count']),
      lowStockThreshold: _asInt(json['low_stock_threshold'], fallback: 3),
      you_xiao_ri_qi: validDateRaw != null ? DateTime.tryParse(validDateRaw.toString()) : null,
      imageUrl: _asString(json['image_url']),
      aiResult: _asString(json['ai_result'] ?? json['raw_response']),
      createdAt: createdAtRaw != null ? DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'spec': spec,
        'category': category,
        'manufacturer': manufacturer,
        'description': description,
        'dosage': dosage,
        'frequency': frequency,
        'precautions': precautions,
        'conflict_tags': conflictTags,
        'stock_count': stockCount,
        'low_stock_threshold': lowStockThreshold,
        'valid_date': you_xiao_ri_qi?.toIso8601String().split('T')[0],
        'expire_date': you_xiao_ri_qi?.toIso8601String().split('T')[0],
        'ai_result': aiResult,
      };
}

class Schedule {
  final int id;
  final int yong_hu_bian_hao;
  final int yao_pin_bian_hao;
  final String? yao_pin_ming_cheng;
  final String ti_xing_shi_jian;
  final DateTime? ji_hua_ri_qi;
  final String? dose;
  final bool shi_fou_qi_yong;
  final Medicine? medicine;

  Schedule({
    required this.id,
    required this.yong_hu_bian_hao,
    required this.yao_pin_bian_hao,
    this.yao_pin_ming_cheng,
    required this.ti_xing_shi_jian,
    this.ji_hua_ri_qi,
    this.dose,
    required this.shi_fou_qi_yong,
    this.medicine,
  });

  int get hour => int.tryParse(ti_xing_shi_jian.split(':').first) ?? 0;

  int get minute {
    final parts = ti_xing_shi_jian.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final medicine = json['medicine'] is Map<String, dynamic> ? Medicine.fromJson(json['medicine']) : null;
    return Schedule(
      id: _asInt(json['id']),
      yong_hu_bian_hao: _asInt(json['user_id']),
      yao_pin_bian_hao: _asInt(json['medicine_id']),
      yao_pin_ming_cheng: _asString(json['medicine_name'] ?? medicine?.name ?? json['title']),
      ti_xing_shi_jian: (json['remind_time'] ?? '08:00').toString(),
      ji_hua_ri_qi: DateTime.tryParse('${json['schedule_date'] ?? ''}'),
      dose: _asString(json['dose']),
      shi_fou_qi_yong: json['is_active'] ?? json['enabled'] ?? true,
      medicine: medicine,
    );
  }
}

class MedicationLog {
  final int id;
  final int? ji_hua_bian_hao;
  final int yong_hu_bian_hao;
  final int yao_pin_bian_hao;
  final String? yao_pin_ming_cheng;
  final DateTime plannedTime;
  final DateTime? actualTime;
  final String status;
  final String? confirmMethod;

  MedicationLog({
    required this.id,
    this.ji_hua_bian_hao,
    required this.yong_hu_bian_hao,
    required this.yao_pin_bian_hao,
    this.yao_pin_ming_cheng,
    required this.plannedTime,
    this.actualTime,
    required this.status,
    this.confirmMethod,
  });

  factory MedicationLog.fromJson(Map<String, dynamic> json) {
    final takenAt = json['actual_time'] ?? json['taken_at'];
    final ji_hua_shi_jian = json['planned_time'] ?? takenAt;
    return MedicationLog(
      id: _asInt(json['id']),
      ji_hua_bian_hao: json['schedule_id'] == null ? null : _asInt(json['schedule_id']),
      yong_hu_bian_hao: _asInt(json['user_id']),
      yao_pin_bian_hao: _asInt(json['medicine_id']),
      yao_pin_ming_cheng: _asString(json['medicine_name']),
      plannedTime: ji_hua_shi_jian != null ? DateTime.tryParse(ji_hua_shi_jian.toString()) ?? DateTime.now() : DateTime.now(),
      actualTime: takenAt != null ? DateTime.tryParse(takenAt.toString()) : null,
      status: (json['status'] ?? 'taken').toString(),
      confirmMethod: _asString(json['confirm_method'] ?? json['note']),
    );
  }
}

class TodaySummary {
  final String date;
  final int total;
  final int taken;
  final int missed;
  final int pending;
  final List<MedicationLog> logs;

  TodaySummary({
    required this.date,
    required this.total,
    required this.taken,
    required this.missed,
    required this.pending,
    required this.logs,
  });

  factory TodaySummary.fromJson(Map<String, dynamic> json) {
    final logs = (json['logs'] as List?)?.map((e) => MedicationLog.fromJson(Map<String, dynamic>.from(e))).toList() ?? [];
    return TodaySummary(
      date: (json['date'] ?? DateTime.now().toIso8601String().split('T').first).toString(),
      total: _asInt(json['total'], fallback: logs.length),
      taken: _asInt(json['taken'], fallback: logs.where((log) => log.status == 'taken').length),
      missed: _asInt(json['missed']),
      pending: _asInt(json['pending']),
      logs: logs,
    );
  }
}

class MedicineAlert {
  final String type;
  final String severity;
  final int yao_pin_bian_hao;
  final String yao_pin_ming_cheng;
  final String message;

  MedicineAlert({
    required this.type,
    required this.severity,
    required this.yao_pin_bian_hao,
    required this.yao_pin_ming_cheng,
    required this.message,
  });

  factory MedicineAlert.fromJson(Map<String, dynamic> json) {
    return MedicineAlert(
      type: (json['type'] ?? 'info').toString(),
      severity: (json['severity'] ?? 'medium').toString(),
      yao_pin_bian_hao: _asInt(json['medicine_id']),
      yao_pin_ming_cheng: (json['medicine_name'] ?? '药品').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
