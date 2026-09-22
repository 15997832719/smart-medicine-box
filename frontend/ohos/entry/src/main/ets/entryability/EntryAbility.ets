import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { BusinessError } from '@ohos.base';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { HarmonyReminderSchedule, ReminderAgentService } from '../reminder/ReminderAgentService';

const REMINDER_CHANNEL = 'smart_medicine_box/reminders';

export default class EntryAbility extends FlutterAbility {
  private reminderChannel: MethodChannel | null = null;
  private pendingReminderPayload: string = '';

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    this.captureReminderPayload(want);
    await super.onCreate(want, launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureReminderPayload(want);
    super.onNewWant(want, launchParam);
    this.flushPendingReminder();
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    this.reminderChannel = new MethodChannel(flutterEngine.dartExecutor, REMINDER_CHANNEL);
    this.reminderChannel.resizeChannelBuffer(16);
    this.reminderChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handleReminderCall(call, result);
      }
    } as MethodCallHandler);
    this.flushPendingReminder();
  }

  private captureReminderPayload(want: Want): void {
    const parameters = want.parameters;
    if (parameters == null) {
      return;
    }
    const payload = parameters.payload;
    if (typeof payload === 'string') {
      this.pendingReminderPayload = payload;
    }
  }

  private flushPendingReminder(): void {
    if (this.pendingReminderPayload.length === 0 || this.reminderChannel == null) {
      return;
    }
    const payload = this.pendingReminderPayload;
    this.pendingReminderPayload = '';
    this.reminderChannel.invokeMethod('onReminderTap', payload);
  }

  private handleReminderCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'requestNotificationPermission') {
      notificationManager.requestEnableNotification(this.context)
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('NOTIFICATION_PERMISSION_FAILED', error.message, null));
      return;
    }

    if (call.method === 'cancelAllReminders') {
      ReminderAgentService.cancelAll()
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('CANCEL_REMINDER_FAILED', error.message, null));
      return;
    }

    if (call.method === 'syncMedicationSchedules') {
      try {
        const rawSchedules = call.argument('schedules') as Object[];
        const schedules: HarmonyReminderSchedule[] = [];
        rawSchedules.forEach((item: Object) => {
          const row = item as Record<string, Object>;
          schedules.push({
            scheduleId: row['schedule_id'] as number,
            userId: row['user_id'] as number,
            hour: row['hour'] as number,
            minute: row['minute'] as number,
            medicineName: row['medicine_name'] as string,
            dose: row['dose'] as string,
            scheduleDate: row['schedule_date'] as string
          });
        });
        ReminderAgentService.sync(schedules)
          .then(() => result.success(true))
          .catch((error: BusinessError) => result.error('SYNC_REMINDER_FAILED', error.message, null));
      } catch (error) {
        const businessError = error as BusinessError;
        result.error('SYNC_REMINDER_FAILED', businessError.message, null);
      }
      return;
    }

    if (call.method === 'scheduleSnooze') {
      ReminderAgentService.scheduleSnooze(
        call.argument('schedule_id') as number,
        call.argument('user_id') as number,
        call.argument('medicine_name') as string,
        call.argument('dose') as string,
        call.argument('delay_seconds') as number
      )
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('SNOOZE_REMINDER_FAILED', error.message, null));
      return;
    }

    result.notImplemented();
  }
}
