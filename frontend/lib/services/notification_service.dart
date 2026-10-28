import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';
import 'harmony_reminder_service.dart';

class MedicationReminderPayload {
  final int ji_hua_bian_hao;
  final int yong_hu_bian_hao;
  final String yao_pin_ming_cheng;
  final String dose;
  final DateTime? ji_hua_shi_jian;
  final bool missed;

  const MedicationReminderPayload({
    required this.ji_hua_bian_hao,
    required this.yong_hu_bian_hao,
    required this.yao_pin_ming_cheng,
    required this.dose,
    this.ji_hua_shi_jian,
    this.missed = false,
  });

  String encode() => jsonEncode({
        'schedule_id': ji_hua_bian_hao,
        'user_id': yong_hu_bian_hao,
        'medicine_name': yao_pin_ming_cheng,
        'dose': dose,
        if (ji_hua_shi_jian != null) 'planned_at': ji_hua_shi_jian!.toIso8601String(),
        'missed': missed,
      });

  static MedicationReminderPayload? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    if (!raw.trimLeft().startsWith('{')) {
      final parts = raw.split(':');
      if (parts.length != 2) return null;
      final ji_hua_bian_hao = int.tryParse(parts[1]);
      if (ji_hua_bian_hao == null) return null;
      return MedicationReminderPayload(
        ji_hua_bian_hao: ji_hua_bian_hao,
        yong_hu_bian_hao: 0,
        yao_pin_ming_cheng: '药品',
        dose: '',
        missed: parts.first == 'missed',
      );
    }

    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final ji_hua_bian_hao = int.tryParse('${data['schedule_id']}');
      if (ji_hua_bian_hao == null) return null;
      return MedicationReminderPayload(
        ji_hua_bian_hao: ji_hua_bian_hao,
        yong_hu_bian_hao: int.tryParse('${data['user_id']}') ?? 0,
        yao_pin_ming_cheng: (data['medicine_name'] ?? '药品').toString(),
        dose: (data['dose'] ?? '').toString(),
        ji_hua_shi_jian: DateTime.tryParse('${data['planned_at'] ?? ''}'),
        missed: data['missed'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}


class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _scheduledIdsKey = 'notification.medication_ids';
  static const _snoozeIdsKey = 'notification.snooze_ids';
  static const _snoozedDoseKeysKey = 'notification.snoozed_dose_keys';
  static const _guardianDigestKey = 'notification.guardian_digest';
  static const _medicationChannel = 'medication_reminders';
  static const _missedChannel = 'missed_medication';
  static const _guardianChannel = 'guardian_alerts';
  static const _snoozeBase = 1800000000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  MedicationReminderPayload? _pendingMedicationReminder;
  void Function(MedicationReminderPayload payload)? onMedicationReminderTap;

  Future<void> initialize() async {
    if (_initialized) return;
    if (HarmonyReminderService.isHarmonyOS) {
      HarmonyReminderService.instance.initialize((payload) {
        final reminder = MedicationReminderPayload.tryParse(payload);
        if (reminder != null) _deliverMedicationReminder(reminder);
      });
      _initialized = true;
      return;
    }
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin
        ?.createNotificationChannel(const AndroidNotificationChannel(
      _medicationChannel,
      'Medication reminders',
      description: 'Reminds the elder to take scheduled medicine',
      importance: Importance.max,
      playSound: true,
    ));
    await androidPlugin
        ?.createNotificationChannel(const AndroidNotificationChannel(
      _missedChannel,
      'Missed medication',
      description: 'Alerts when a medication plan remains unconfirmed',
      importance: Importance.max,
      playSound: true,
    ));
    await androidPlugin
        ?.createNotificationChannel(const AndroidNotificationChannel(
      _guardianChannel,
      'Guardian alerts',
      description: 'Medication risk and missed-dose alerts for family members',
      importance: Importance.high,
      playSound: true,
    ));
    _initialized = true;

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _handleNotificationResponse(launchDetails!.notificationResponse);
      }
    } catch (_) {
      
    }
  }

  Future<bool> requestPermissions({bool requestExactAlarm = true}) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) {
      return HarmonyReminderService.instance.requestPermission();
    }
    var granted = true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    if (androidGranted != null) granted = androidGranted && granted;

    if (requestExactAlarm) {
      final exactAlarmGranted = await android?.requestExactAlarmsPermission();
      if (exactAlarmGranted != null) granted = exactAlarmGranted && granted;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted =
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
    if (iosGranted != null) granted = iosGranted && granted;
    return granted;
  }

  Future<void> syncMedicationSchedules(
    List<Schedule> schedules, {
    TodaySummary? today,
  }) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) {
      await HarmonyReminderService.instance.syncMedicationSchedules(
        schedules,
        today: today,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final oldIds = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    for (final value in oldIds) {
      final id = int.tryParse(value);
      if (id != null) await _plugin.cancel(id);
    }

    final ids = <int>[];
    final now = tz.TZDateTime.now(tz.local);
    final activeSchedules =
        schedules.where((item) => item.shi_fou_qi_yong && item.id > 0).toList();
    final confirmedDoses = _confirmedDoseKeys(today);
    final snoozedDoses =
        (prefs.getStringList(_snoozedDoseKeysKey) ?? <String>[]).toSet();
    
    
    final dailyScheduleCount =
        activeSchedules.where((item) => item.ji_hua_ri_qi == null).length;
    final daysToSchedule = dailyScheduleCount == 0
        ? 0
        : (60 ~/ (dailyScheduleCount * 2)).clamp(1, 30).toInt();

    for (final schedule in activeSchedules) {
      final specificDate = schedule.ji_hua_ri_qi;
      final scheduleDays = specificDate == null ? daysToSchedule : 1;
      for (var offset = 0; offset < scheduleDays; offset++) {
        final day = specificDate ??
            DateTime(now.year, now.month, now.day + offset);
        final ji_hua_shi_jian = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            schedule.hour, schedule.minute);
        final doseKey = _doseKey(schedule.id, ji_hua_shi_jian);
        if (confirmedDoses.contains(doseKey) ||
            snoozedDoses.contains(doseKey)) {
          continue;
        }

        if (ji_hua_shi_jian.isAfter(now)) {
          final medicationId =
              _notificationId(schedule.id, ji_hua_shi_jian, missed: false);
          await _schedule(
            medicationId,
            schedule.yao_pin_ming_cheng ?? '用药提醒',
            '${schedule.yao_pin_ming_cheng ?? '药品'}${_doseText(schedule.dose)}，服药时间到了，请及时确认。',
            ji_hua_shi_jian,
            _medicationDetails(fullScreen: true),
            payload: MedicationReminderPayload(
              ji_hua_bian_hao: schedule.id,
              yong_hu_bian_hao: schedule.yong_hu_bian_hao,
              yao_pin_ming_cheng: schedule.yao_pin_ming_cheng ?? '药品',
              dose: schedule.dose ?? '',
              ji_hua_shi_jian: ji_hua_shi_jian,
            ).encode(),
          );
          ids.add(medicationId);
        }

        final missedAt = ji_hua_shi_jian.add(const Duration(minutes: 90));
        if (missedAt.isAfter(now)) {
          final missedId =
              _notificationId(schedule.id, ji_hua_shi_jian, missed: true);
          await _schedule(
            missedId,
            schedule.yao_pin_ming_cheng ?? '漏服提醒',
            '${schedule.yao_pin_ming_cheng ?? '药品'}${_doseText(schedule.dose)}，已超过计划时间，请尽快核实是否服药。',
            missedAt,
            _missedDetails(),
            payload: MedicationReminderPayload(
              ji_hua_bian_hao: schedule.id,
              yong_hu_bian_hao: schedule.yong_hu_bian_hao,
              yao_pin_ming_cheng: schedule.yao_pin_ming_cheng ?? '药品',
              dose: schedule.dose ?? '',
              ji_hua_shi_jian: ji_hua_shi_jian,
              missed: true,
            ).encode(),
          );
          ids.add(missedId);
        }
      }
    }

    await prefs.setStringList(
        _scheduledIdsKey, ids.map((id) => '$id').toList());
  }

  Future<void> markMedicationTaken(
    int ji_hua_bian_hao, {
    DateTime? ji_hua_shi_jian,
  }) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) return;
    final targetDate = (ji_hua_shi_jian ?? DateTime.now()).toLocal();
    await _plugin.cancel(
        _notificationId(ji_hua_bian_hao, targetDate, missed: false));
    await _plugin.cancel(_notificationId(ji_hua_bian_hao, targetDate, missed: true));

    final snoozeId = _snoozeBase + (ji_hua_bian_hao.abs() % 100000);
    await _plugin.cancel(snoozeId);
    final prefs = await SharedPreferences.getInstance();
    final snoozeIds = prefs.getStringList(_snoozeIdsKey) ?? <String>[];
    snoozeIds.remove('$snoozeId');
    await prefs.setStringList(_snoozeIdsKey, snoozeIds);
    final snoozedKeys =
        prefs.getStringList(_snoozedDoseKeysKey) ?? <String>[];
    snoozedKeys.remove(_doseKey(ji_hua_bian_hao, targetDate));
    await prefs.setStringList(_snoozedDoseKeysKey, snoozedKeys);
  }

  Future<void> cancelMissedReminder(
    int ji_hua_bian_hao, {
    DateTime? ji_hua_shi_jian,
  }) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) return;
    final targetDate = (ji_hua_shi_jian ?? DateTime.now()).toLocal();
    await _plugin.cancel(_notificationId(ji_hua_bian_hao, targetDate, missed: true));
  }

  Future<void> scheduleSnooze({
    required int ji_hua_bian_hao,
    required int yong_hu_bian_hao,
    required String yao_pin_ming_cheng,
    required String dose,
    DateTime? ji_hua_shi_jian,
    Duration delay = const Duration(minutes: 30),
  }) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) {
      await HarmonyReminderService.instance.scheduleSnooze(
        ji_hua_bian_hao: ji_hua_bian_hao,
        yong_hu_bian_hao: yong_hu_bian_hao,
        yao_pin_ming_cheng: yao_pin_ming_cheng,
        dose: dose,
        delay: delay,
      );
      return;
    }
    final id = _snoozeBase + (ji_hua_bian_hao.abs() % 100000);
    await _plugin.cancel(id);
    final sourceDate = (ji_hua_shi_jian ?? DateTime.now()).toLocal();
    await _plugin.cancel(
        _notificationId(ji_hua_bian_hao, sourceDate, missed: true));
    final at = tz.TZDateTime.now(tz.local).add(delay);
    await _schedule(
      id,
      yao_pin_ming_cheng,
      '$yao_pin_ming_cheng${_doseText(dose)}，将在30分钟后再次提醒。',
      at,
      _medicationDetails(fullScreen: true),
      payload: MedicationReminderPayload(
        ji_hua_bian_hao: ji_hua_bian_hao,
        yong_hu_bian_hao: yong_hu_bian_hao,
        yao_pin_ming_cheng: yao_pin_ming_cheng,
        dose: dose,
        ji_hua_shi_jian: at,
      ).encode(),
    );

    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_snoozeIdsKey) ?? <String>[];
    if (!ids.contains('$id')) {
      ids.add('$id');
      await prefs.setStringList(_snoozeIdsKey, ids);
    }
    final snoozedKeys =
        prefs.getStringList(_snoozedDoseKeysKey) ?? <String>[];
    final doseKey = _doseKey(ji_hua_bian_hao, sourceDate);
    if (!snoozedKeys.contains(doseKey)) {
      snoozedKeys.add(doseKey);
      await prefs.setStringList(_snoozedDoseKeysKey, snoozedKeys);
    }
  }

  Future<void> notifyGuardianAlerts(List<MedicineAlert> alerts,
      {TodaySummary? today}) async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) return;
    final missed = today?.missed ?? 0;
    if (alerts.isEmpty && missed == 0) return;
    final digest =
        '${DateTime.now().toIso8601String().substring(0, 10)}|$missed|${alerts.map((item) => '${item.type}:${item.yao_pin_bian_hao}').join(',')}';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_guardianDigestKey) == digest) return;
    await prefs.setString(_guardianDigestKey, digest);

    final first = alerts.isNotEmpty
        ? alerts.first.message
        : '今日有 $missed 项未确认用药，请及时查看。';
    await _plugin.show(
      1900000001,
      '用药风险提醒',
      first,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _guardianChannel,
          'Guardian alerts',
          channelDescription:
              'Medication risk and missed-dose alerts for family members',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(sound: 'default'),
      ),
      payload: 'guardian',
    );
  }

  Future<void> qing_chu_yong_yao_ji_hua() async {
    await initialize();
    if (HarmonyReminderService.isHarmonyOS) {
      await HarmonyReminderService.instance.cancelAll();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>[
      ...?prefs.getStringList(_scheduledIdsKey),
      ...?prefs.getStringList(_snoozeIdsKey),
    ];
    for (final value in ids) {
      final id = int.tryParse(value);
      if (id != null) await _plugin.cancel(id);
    }
    await prefs.remove(_scheduledIdsKey);
    await prefs.remove(_snoozeIdsKey);
    await prefs.remove(_snoozedDoseKeysKey);
  }

  MedicationReminderPayload? takePendingMedicationReminder() {
    final reminder = _pendingMedicationReminder;
    _pendingMedicationReminder = null;
    return reminder;
  }

  NotificationDetails _medicationDetails({required bool fullScreen}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _medicationChannel,
        'Medication reminders',
        channelDescription:
            'Reminds the elder to take scheduled medicine',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: fullScreen,
        playSound: true,
        enableVibration: true,
        autoCancel: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      ),
    );
  }

  NotificationDetails _missedDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _missedChannel,
        'Missed medication',
        channelDescription:
            'Alerts when a medication plan remains unconfirmed',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(sound: 'default'),
    );
  }

  String _doseText(String? dose) =>
      dose == null || dose.trim().isEmpty ? '' : '，剂量 $dose';

  String _doseKey(int ji_hua_bian_hao, DateTime date) {
    final local = date.toLocal();
    return '$ji_hua_bian_hao:${local.year}-${local.month}-${local.day}';
  }

  Set<String> _confirmedDoseKeys(TodaySummary? today) {
    final keys = <String>{};
    if (today == null) return keys;
    for (final log in today.logs) {
      if (log.status != 'taken' || log.ji_hua_bian_hao == null) continue;
      keys.add(_doseKey(log.ji_hua_bian_hao!, log.plannedTime));
    }
    return keys;
  }

  int _notificationId(int ji_hua_bian_hao, DateTime date, {required bool missed}) {
    final local = date.toLocal();
    final dayKey = (local.year * 372 + local.month * 31 + local.day) % 50000;
    final scheduleKey = ji_hua_bian_hao.abs() % 10000;
    return scheduleKey * 100000 + dayKey + (missed ? 50000 : 0);
  }

  
  
  Future<void> _schedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime when,
    NotificationDetails details, {
    UILocalNotificationDateInterpretation? uiLocalNotificationDateInterpretation,
    String? payload,
  }) async {
    try {
      
      await _plugin.zonedSchedule(id, title, body, when, details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              uiLocalNotificationDateInterpretation ??
                  UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload);
    } on Object {
      try {
        await _plugin.zonedSchedule(id, title, body, when, details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                uiLocalNotificationDateInterpretation ??
                    UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload);
      } on Object {
        await _plugin.zonedSchedule(id, title, body, when, details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                uiLocalNotificationDateInterpretation ??
                    UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload);
      }
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  void _handleNotificationResponse(NotificationResponse? response) {
    if (response == null) return;
    final reminder = MedicationReminderPayload.tryParse(response.payload);
    if (reminder != null) _deliverMedicationReminder(reminder);
  }

  void _deliverMedicationReminder(MedicationReminderPayload reminder) {
    final handler = onMedicationReminderTap;
    if (handler != null) {
      handler(reminder);
    } else {
      _pendingMedicationReminder = reminder;
    }
  }
}
