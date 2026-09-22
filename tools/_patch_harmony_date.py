from pathlib import Path
base = Path(r'D:\smart-medicine-box\frontend\ohos\entry\src\main\ets')
service = base / 'reminder/ReminderAgentService.ets'
s = service.read_text(encoding='utf-8')
def rep(old,new,expected=1):
    global s
    count=s.count(old)
    if count!=expected: raise SystemExit(f'service count={count}, expected={expected}: {old[:80]}')
    s=s.replace(old,new)
rep("  medicineName: string;\n  dose: string;\n}", "  medicineName: string;\n  dose: string;\n  scheduleDate?: string;\n}")
rep("    for (const schedule of schedules) {\n      await ReminderAgentService.publishDaily(schedule);\n    }", "    for (const schedule of schedules) {\n      if (schedule.scheduleDate) {\n        await ReminderAgentService.publishSpecificDate(schedule);\n      } else {\n        await ReminderAgentService.publishDaily(schedule);\n      }\n    }")
rep("  private static async publishDaily(schedule: HarmonyReminderSchedule): Promise<void> {", """  private static async publishSpecificDate(schedule: HarmonyReminderSchedule): Promise<void> {
    const hourText = schedule.hour.toString().padStart(2, '0');
    const minuteText = schedule.minute.toString().padStart(2, '0');
    const target = new Date(`${schedule.scheduleDate}T${hourText}:${minuteText}:00+08:00`);
    const delaySeconds = Math.floor((target.getTime() - Date.now()) / 1000);
    if (delaySeconds <= 0) {
      return;
    }
    const request: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      triggerTimeInSeconds: delaySeconds,
      title: '用药提醒',
      content: ReminderAgentService.content(schedule.medicineName, schedule.dose),
      expiredContent: '本次服药提醒已过期，请核实是否服药。',
      snoozeContent: '稍后再次提醒服药。',
      notificationId: schedule.scheduleId,
      groupId: ReminderAgentService.groupId,
      ringDuration: 10,
      snoozeTimes: 2,
      timeInterval: 5,
      tapDismissed: false,
      actionButton: [
        {
          title: '稍后提醒',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE
        },
        {
          title: '关闭',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }
      ],
      wantAgent: ReminderAgentService.createWantAgent(
        schedule.scheduleId,
        schedule.userId,
        schedule.medicineName,
        schedule.dose,
        false
      ),
      maxScreenWantAgent: {
        pkgName: ReminderAgentService.bundleName,
        abilityName: ReminderAgentService.abilityName
      }
    };
    await reminderAgentManager.publishReminder(request);
  }

  private static async publishDaily(schedule: HarmonyReminderSchedule): Promise<void> {""")
service.write_text(s,encoding='utf-8')

entry = base / 'entryability/EntryAbility.ets'
t = entry.read_text(encoding='utf-8')
old = "            medicineName: row['medicine_name'] as string,\n            dose: row['dose'] as string\n"
new = "            medicineName: row['medicine_name'] as string,\n            dose: row['dose'] as string,\n            scheduleDate: row['schedule_date'] as string\n"
if t.count(old)!=1: raise SystemExit(f'entry count={t.count(old)}')
entry.write_text(t.replace(old,new,1),encoding='utf-8')
print('harmony date patch applied')
