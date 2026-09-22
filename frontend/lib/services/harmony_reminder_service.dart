import 'dart:io';

import 'package:flutter/services.dart';

import '../models/medicine.dart';

class HarmonyReminderService {
  HarmonyReminderService._();

  static final HarmonyReminderService instance = HarmonyReminderService._();

  static const _channel = MethodChannel('smart_medicine_box/reminders');

  static bool get isHarmonyOS {
    final system = Platform.operatingSystem.toLowerCase();
    return system == 'ohos' || system.contains('harmony');
  }

  void initialize(void Function(String payload) onReminderTap) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onReminderTap') return null;
      final arguments = call.arguments;
      if (arguments is String) {
        onReminderTap(arguments);
      } else if (arguments is Map) {
        onReminderTap((arguments['payload'] ?? '').toString());
      }
      return null;
    });
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
          true;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncMedicationSchedules(
    List<Schedule> schedules, {
    TodaySummary? today,
  }) async {
    final payload = schedules
        .where((schedule) => schedule.shi_fou_qi_yong && schedule.id > 0)
        .map((schedule) => {
              'schedule_id': schedule.id,
              'user_id': schedule.yong_hu_bian_hao,
              'hour': schedule.hour,
              'minute': schedule.minute,
              'medicine_name': schedule.yao_pin_ming_cheng ?? '药品',
              'dose': schedule.dose ?? '',
              'schedule_date': schedule.ji_hua_ri_qi?.toIso8601String().split('T').first,
            })
        .toList();
    await _channel.invokeMethod<void>('syncMedicationSchedules', {
      'schedules': payload,
    });
  }

  Future<void> scheduleSnooze({
    required int ji_hua_bian_hao,
    required int yong_hu_bian_hao,
    required String yao_pin_ming_cheng,
    required String dose,
    Duration delay = const Duration(minutes: 30),
  }) async {
    await _channel.invokeMethod<void>('scheduleSnooze', {
      'schedule_id': ji_hua_bian_hao,
      'user_id': yong_hu_bian_hao,
      'medicine_name': yao_pin_ming_cheng,
      'dose': dose,
      'delay_seconds': delay.inSeconds,
    });
  }

  Future<void> cancelAll() async {
    await _channel.invokeMethod<void>('cancelAllReminders');
  }
}
