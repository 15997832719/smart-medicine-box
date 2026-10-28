import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import media from '@ohos.multimedia.media';
import asset from '@ohos.security.asset';
import fileIo from '@ohos.file.fs';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import router from '@ohos.router';
import { FaceCameraOptions, FaceCameraOutcome, FaceCameraSession } from '../facecamera/FaceCameraSession';
import { HarmonyReminderSchedule, ReminderAgentService } from '../reminder/ReminderAgentService';

const REMINDER_CHANNEL = 'smart_medicine_box/reminders';
const VOICE_CAPTURE_CHANNEL = 'smart_medicine_box/voice_capture';
const SECURE_STORE_CHANNEL = 'smart_medicine_box/secure_store';
const TTS_CHANNEL = 'smart_medicine_box/tts';
const FACE_CAMERA_CHANNEL = 'smart_medicine_box/face_camera';

export default class EntryAbility extends FlutterAbility {
  private reminderChannel: MethodChannel | null = null;
  private voiceCaptureChannel: MethodChannel | null = null;
  private secureStoreChannel: MethodChannel | null = null;
  private ttsChannel: MethodChannel | null = null;
  private faceCameraChannel: MethodChannel | null = null;
  private faceCameraPending: boolean = false;
  private ttsPlayer: media.AVPlayer | null = null;
  private ttsFile: fileIo.File | null = null;
  private ttsResult: MethodResult | null = null;
  private voiceRecorder: media.AVRecorder | null = null;
  private voiceFile: fileIo.File | null = null;
  private voiceFilePath: string = '';
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

    this.voiceCaptureChannel = new MethodChannel(flutterEngine.dartExecutor, VOICE_CAPTURE_CHANNEL);
    this.voiceCaptureChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handleVoiceCaptureCall(call, result);
      }
    } as MethodCallHandler);

    this.ttsChannel = new MethodChannel(flutterEngine.dartExecutor, TTS_CHANNEL);
    this.ttsChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handleTtsCall(call, result);
      }
    } as MethodCallHandler);

    this.faceCameraChannel = new MethodChannel(flutterEngine.dartExecutor, FACE_CAMERA_CHANNEL);
    this.faceCameraChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handleFaceCameraCall(call, result);
      }
    } as MethodCallHandler);
  }

  private async releaseTtsPlayer(): Promise<void> {
    const player = this.ttsPlayer;
    const file = this.ttsFile;
    this.ttsPlayer = null;
    this.ttsFile = null;
    if (player != null) {
      try {
        await player.release();
      } catch (_) {
      }
    }
    if (file != null) {
      try {
        fileIo.closeSync(file);
      } catch (_) {
      }
    }
  }

  private async playTtsFile(path: string): Promise<void> {
    await this.releaseTtsPlayer();
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const size = fileIo.statSync(path).size;
    const player = await media.createAVPlayer();
    this.ttsPlayer = player;
    this.ttsFile = file;
    player.on('stateChange', (state: string): void => {
      if (state === 'initialized') {
        player.prepare();
      } else if (state === 'prepared') {
        player.play();
      } else if (state === 'completed') {
        this.completeTts(true);
      }
    });
    player.on('error', (error: BusinessError): void => {
      this.completeTts(false, error.message);
    });
    player.fdSrc = { fd: file.fd, offset: 0, length: size };
  }

  private completeTts(success: boolean, message?: string): void {
    const result = this.ttsResult;
    this.ttsResult = null;
    this.releaseTtsPlayer();
    if (result == null) {
      return;
    }
    if (success) {
      result.success(true);
    } else {
      result.error('TTS_PLAY_FAILED', message ?? 'tts play failed', null);
    }
  }

  private handleTtsCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'isAvailable') {
      result.success(true);
      return;
    }
    if (call.method === 'playFile') {
      if (this.ttsResult != null) {
        result.error('TTS_BUSY', 'tts is already playing', null);
        return;
      }
      const path = call.argument('path') as string;
      this.ttsResult = result;
      this.playTtsFile(path).catch((error: BusinessError) => {
        this.completeTts(false, error.message);
      });
      return;
    }
    if (call.method === 'stop') {
      this.completeTts(true);
      return;
    }
    result.notImplemented();
  }

  private stringToBytes(value: string): Uint8Array {
    const bytes = new Uint8Array(value.length);
    for (let index = 0; index < value.length; index++) {
      bytes[index] = value.charCodeAt(index);
    }
    return bytes;
  }

  private bytesToString(value: Uint8Array): string {
    let result = '';
    for (let index = 0; index < value.length; index++) {
      result += String.fromCharCode(value[index]);
    }
    return result;
  }

  private async secureWrite(key: string, value: string): Promise<void> {
    const alias = this.stringToBytes(key);
    const removeQuery = new Map<asset.Tag, asset.Value>();
    removeQuery.set(asset.Tag.ALIAS, alias);
    try {
      await asset.remove(removeQuery);
    } catch (_) {
    }
    const attributes = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, alias);
    attributes.set(asset.Tag.SECRET, this.stringToBytes(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    await asset.add(attributes);
  }

  private async secureRead(key: string): Promise<string | null> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.stringToBytes(key));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const result = await asset.query(query);
    if (result.length === 0) {
      return null;
    }
    const secret = result[0].get(asset.Tag.SECRET);
    if (secret instanceof Uint8Array) {
      return this.bytesToString(secret);
    }
    return null;
  }

  private async secureDelete(key: string): Promise<void> {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.stringToBytes(key));
    try {
      await asset.remove(query);
    } catch (_) {
    }
  }

  private handleSecureStoreCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'write') {
      const key = call.argument('key') as string;
      const value = call.argument('value') as string;
      this.secureWrite(key, value)
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('SECURE_STORE_WRITE_FAILED', error.message, null));
      return;
    }
    if (call.method === 'read') {
      const key = call.argument('key') as string;
      this.secureRead(key)
        .then((value: string | null) => result.success(value))
        .catch((error: BusinessError) => result.error('SECURE_STORE_READ_FAILED', error.message, null));
      return;
    }
    if (call.method === 'delete') {
      const key = call.argument('key') as string;
      this.secureDelete(key)
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('SECURE_STORE_DELETE_FAILED', error.message, null));
      return;
    }
    result.notImplemented();
  }

  private async hasMicrophonePermission(): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const status = await manager.checkAccessToken(
      this.context.applicationInfo.uid,
      'ohos.permission.MICROPHONE'
    );
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async requestMicrophonePermission(): Promise<boolean> {
    if (await this.hasMicrophonePermission()) {
      return true;
    }
    const permissions: Array<Permissions> = ['ohos.permission.MICROPHONE'];
    const manager = abilityAccessCtrl.createAtManager();
    const result = await manager.requestPermissionsFromUser(this.context, permissions);
    return result.authResults.length > 0 && result.authResults.every((status: number) => status === 0);
  }

  private async startVoiceRecording(): Promise<string> {
    if (this.voiceRecorder != null) {
      throw new Error('recording already active');
    }
    if (!await this.requestMicrophonePermission()) {
      throw new Error('microphone permission denied');
    }

    const path = `${this.context.cacheDir}/voice_${Date.now()}.m4a`;
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
    );
    const recorder = await media.createAVRecorder();
    try {
      await recorder.prepare({
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 64000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 16000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${file.fd}`
      });
      await recorder.start();
      this.voiceRecorder = recorder;
      this.voiceFile = file;
      this.voiceFilePath = path;
      return path;
    } catch (error) {
      fileIo.closeSync(file);
      try {
        fileIo.unlinkSync(path);
      } catch (_) {
      }
      throw new Error((error as BusinessError).message);
    }
  }

  private async stopVoiceRecording(): Promise<string> {
    const recorder = this.voiceRecorder;
    const file = this.voiceFile;
    const path = this.voiceFilePath;
    if (recorder == null || file == null || path.length === 0) {
      throw new Error('recording is not active');
    }
    this.voiceRecorder = null;
    this.voiceFile = null;
    this.voiceFilePath = '';
    try {
      await recorder.stop();
    } finally {
      await recorder.release();
      fileIo.closeSync(file);
    }
    return path;
  }

  private async cancelVoiceRecording(): Promise<void> {
    const recorder = this.voiceRecorder;
    const file = this.voiceFile;
    const path = this.voiceFilePath;
    this.voiceRecorder = null;
    this.voiceFile = null;
    this.voiceFilePath = '';
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {
      }
      try {
        await recorder.release();
      } catch (_) {
      }
    }
    if (file != null) {
      try {
        fileIo.closeSync(file);
      } catch (_) {
      }
    }
    if (path.length > 0) {
      try {
        fileIo.unlinkSync(path);
      } catch (_) {
      }
    }
  }

  private handleVoiceCaptureCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'hasMicrophonePermission') {
      this.hasMicrophonePermission()
        .then((granted: boolean) => result.success(granted))
        .catch((error: BusinessError) => result.error('VOICE_PERMISSION_CHECK_FAILED', error.message, null));
      return;
    }
    if (call.method === 'requestMicrophonePermission') {
      this.requestMicrophonePermission()
        .then((granted: boolean) => result.success(granted))
        .catch((error: BusinessError) => result.error('VOICE_PERMISSION_REQUEST_FAILED', error.message, null));
      return;
    }
    if (call.method === 'startRecording') {
      this.startVoiceRecording()
        .then((path: string) => result.success(path))
        .catch((error: BusinessError) => result.error('VOICE_START_FAILED', error.message, null));
      return;
    }
    if (call.method === 'stopRecording') {
      this.stopVoiceRecording()
        .then((path: string) => result.success(path))
        .catch((error: BusinessError) => result.error('VOICE_STOP_FAILED', error.message, null));
      return;
    }
    if (call.method === 'cancelRecording') {
      this.cancelVoiceRecording()
        .then(() => result.success(true))
        .catch((error: BusinessError) => result.error('VOICE_CANCEL_FAILED', error.message, null));
      return;
    }
    result.notImplemented();
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

  private handleFaceCameraCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'isAvailable') {
      result.success(true);
      return;
    }
    if (call.method === 'capture') {
      if (this.faceCameraPending) {
        result.error('FACE_CAMERA_BUSY', '刷脸页面已打开，请稍候', null);
        return;
      }
      const options: FaceCameraOptions = {
        mode: this.stringArgument(call, 'mode', 'login'),
        delayMs: this.numberArgument(call, 'auto_capture_delay_ms', 2000),
        hint: this.stringArgument(call, 'hint', '请把脸放进圆框')
      };
      this.faceCameraPending = true;
      FaceCameraSession.begin((outcome: FaceCameraOutcome): void => {
        this.faceCameraPending = false;
        if (outcome.ok) {
          result.success(outcome.path);
        } else {
          result.error(outcome.code, outcome.message, null);
        }
      }, options);
      router.pushUrl({ url: 'pages/FaceCameraPage' }).catch((error: BusinessError) => {
        this.faceCameraPending = false;
        FaceCameraSession.clear();
        result.error('FACE_CAMERA_UNAVAILABLE', error.message, null);
      });
      return;
    }
    result.notImplemented();
  }

  private numberArgument(call: MethodCall, name: string, fallback: number): number {
    const value = call.argument(name) as number;
    if (typeof value === 'number' && value > 0) {
      return value;
    }
    return fallback;
  }

  private stringArgument(call: MethodCall, name: string, fallback: string): string {
    const value = call.argument(name) as string;
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
    return fallback;
  }
}
