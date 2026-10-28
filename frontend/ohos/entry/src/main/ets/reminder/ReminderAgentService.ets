import reminderAgentManager from '@ohos.reminderAgentManager';

export interface HarmonyReminderSchedule {
  scheduleId: number;
  userId: number;
  hour: number;
  minute: number;
  medicineName: string;
  dose: string;
  scheduleDate?: string;
}

export class ReminderAgentService {
  private static readonly bundleName = 'com.smartmedicine.smart_medicine_box';
  private static readonly abilityName = 'EntryAbility';
  private static readonly groupId = 'smart-medicine-box';

  static async sync(schedules: HarmonyReminderSchedule[]): Promise<void> {
    await reminderAgentManager.cancelAllReminders();
    for (const schedule of schedules) {
      if (schedule.scheduleDate) {
        await ReminderAgentService.publishSpecificDate(schedule);
      } else {
        await ReminderAgentService.publishDaily(schedule);
      }
    }
  }

  static async scheduleSnooze(
    scheduleId: number,
    userId: number,
    medicineName: string,
    dose: string,
    delaySeconds: number
  ): Promise<void> {
    const request: reminderAgentManager.ReminderRequestTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      triggerTimeInSeconds: delaySeconds,
      title: medicineName,
      content: medicineName + dose + '，请确认是否已经服药。',
      notificationId: ReminderAgentService.snoozeNotificationId(scheduleId),
      groupId: ReminderAgentService.groupId,
      ringDuration: 10,
      snoozeTimes: 1,
      timeInterval: 5,
      tapDismissed: true,
      wantAgent: ReminderAgentService.createWantAgent(scheduleId, userId, medicineName, dose, true),
      maxScreenWantAgent: {
        pkgName: ReminderAgentService.bundleName,
        abilityName: ReminderAgentService.abilityName
      }
    };
    await reminderAgentManager.publishReminder(request);
  }

  static async cancelAll(): Promise<void> {
    await reminderAgentManager.cancelAllReminders();
  }

  private static async publishSpecificDate(schedule: HarmonyReminderSchedule): Promise<void> {
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
      title: schedule.medicineName,
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

  private static async publishDaily(schedule: HarmonyReminderSchedule): Promise<void> {
    const request: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: schedule.hour,
      minute: schedule.minute,
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: '服药提醒',
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

  private static createWantAgent(
    scheduleId: number,
    userId: number,
    medicineName: string,
    dose: string,
    missed: boolean
  ): reminderAgentManager.WantAgent {
    const payloadMap: Record<string, Object> = {};
    payloadMap['schedule_id'] = scheduleId;
    payloadMap['user_id'] = userId;
    payloadMap['medicine_name'] = medicineName;
    payloadMap['dose'] = dose;
    payloadMap['missed'] = missed;
    const payload = JSON.stringify(payloadMap);
    return {
      pkgName: ReminderAgentService.bundleName,
      abilityName: ReminderAgentService.abilityName,
      parameters: {
        payload: payload
      }
    };
  }

  private static content(medicineName: string, dose: string): string {
    return medicineName + '，剂量 ' + dose + '，请按时服药并确认。';
  }

  private static snoozeNotificationId(scheduleId: number): number {
    return 200000 + (scheduleId % 100000);
  }
}
