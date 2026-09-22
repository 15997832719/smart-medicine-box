from pathlib import Path
p = Path(r'D:\smart-medicine-box\frontend/lib/services/notification_service.dart')
s = p.read_text(encoding='utf-8')
old = """    final daysToSchedule = activeSchedules.isEmpty
        ? 0
        : (60 ~/ (activeSchedules.length * 2)).clamp(1, 30).toInt();

    for (final schedule in activeSchedules) {
      for (var offset = 0; offset < daysToSchedule; offset++) {
        final day = DateTime(now.year, now.month, now.day + offset);
        final plannedAt = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            schedule.hour, schedule.minute);
"""
new = """    final dailyScheduleCount =
        activeSchedules.where((item) => item.scheduleDate == null).length;
    final daysToSchedule = dailyScheduleCount == 0
        ? 0
        : (60 ~/ (dailyScheduleCount * 2)).clamp(1, 30).toInt();

    for (final schedule in activeSchedules) {
      final specificDate = schedule.scheduleDate;
      final scheduleDays = specificDate == null ? daysToSchedule : 1;
      for (var offset = 0; offset < scheduleDays; offset++) {
        final day = specificDate ??
            DateTime(now.year, now.month, now.day + offset);
        final plannedAt = tz.TZDateTime(tz.local, day.year, day.month, day.day,
            schedule.hour, schedule.minute);
"""
if s.count(old)!=1: raise SystemExit(f'loop pattern count={s.count(old)}')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('notification date scheduling patch applied')
