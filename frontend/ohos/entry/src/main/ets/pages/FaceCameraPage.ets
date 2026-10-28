/*
 * 慧药管家 鸿蒙 A 版刷脸页（A 版：实时预览 + 圆框引导 + 自动抓拍，无活体检测）
 * 流程：前置摄像头预览 -> 圆框引导 -> 倒计时 -> 自动抓拍 -> 返回 JPEG 给 Flutter
 * 说明：本页只负责取图，比对逻辑仍在后端 /face/login 与 /face/enroll。
 */
import common from '@ohos.app.ability.common';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import camera from '@ohos.multimedia.camera';
import image from '@ohos.multimedia.image';
import fileIo from '@ohos.file.fs';
import display from '@ohos.display';
import router from '@ohos.router';
import { BusinessError } from '@ohos.base';
import { FaceCameraOptions, FaceCameraOutcome, FaceCameraSession } from '../facecamera/FaceCameraSession';

const PERMISSION_UNKNOWN: number = 0;
const PERMISSION_GRANTED: number = 1;
const PERMISSION_DENIED: number = 2;
const DEFAULT_DELAY_MS: number = 2000;
const MAX_DELAY_MS: number = 8000;
const ERROR_DISPLAY_MS: number = 1500;
const SUCCESS_DISPLAY_MS: number = 220;
const CAPTURE_WATCHDOG_MS: number = 6000;
const PHOTO_AREA_LIMIT: number = 1920 * 1440;

@Entry
@Component
struct FaceCameraPage {
  @State hintText: string = '请把脸放进圆框';
  @State statusText: string = '正在准备摄像头…';
  @State countdownText: string = '';
  @State errorText: string = '';
  @State ready: boolean = false;

  private previewController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private permissionState: number = PERMISSION_UNKNOWN;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private photoSession: camera.PhotoSession | null = null;
  private countdownTimer: number = -1;
  private autoTimer: number = -1;
  private exitTimer: number = -1;
  private watchdogTimer: number = -1;
  private opening: boolean = false;
  private capturing: boolean = false;
  private settled: boolean = false;
  private options: FaceCameraOptions = { mode: 'login', delayMs: DEFAULT_DELAY_MS, hint: '' };
  private abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.options = FaceCameraSession.currentOptions();
    if (this.options.hint.length > 0) {
      this.hintText = this.options.hint;
    }
    this.ensurePermission();
  }

  aboutToDisappear(): void {
    this.releaseCamera();
    if (!this.settled) {
      this.settled = true;
      FaceCameraSession.finish({ ok: false, code: 'CANCELLED', message: '已取消刷脸', path: '' });
    }
  }

  onBackPress(): boolean {
    if (!this.settled) {
      this.settle(false, 'CANCELLED', '已取消刷脸', '');
    }
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({ id: 'smb_face_preview', type: XComponentType.SURFACE, controller: this.previewController })
        .width('100%')
        .height('100%')
        .renderFit(RenderFit.RESIZE_COVER)
        .onLoad(() => {
          this.surfaceId = this.previewController.getXComponentSurfaceId();
          if (this.permissionState === PERMISSION_GRANTED) {
            this.openCamera();
          }
        })

      Column()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '42%'],
          radius: '60%',
          colors: [[Color.Transparent, 0.0], [Color.Transparent, 0.40], ['#000000', 0.72], ['#000000', 0.86]]
        })

      Circle({ width: 280, height: 280 })
        .fillOpacity(0)
        .stroke('#FFFFFF')
        .strokeWidth(6)
        .opacity(0.9)
        .offset({ y: -70 })

      Column() {
        Column() {
          Text(this.hintText)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.countdownText.length > 0) {
            Text(this.countdownText)
              .fontSize(42)
              .fontWeight(FontWeight.Bold)
              .fontColor('#7CFFB2')
              .margin({ top: 6 })
          }
          Text(this.statusText)
            .fontSize(20)
            .fontColor('#F1F8E9')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 10 })
          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(20)
              .fontColor('#FFCDD2')
              .textAlign(TextAlign.Center)
              .width('100%')
              .margin({ top: 10 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Column() {
          Button('立即拍摄')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(64)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#2E7D32')
            .enabled(this.ready && !this.capturing && !this.settled)
            .onClick(() => {
              this.captureNow();
            })
          Button('取消')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(56)
            .fontSize(22)
            .fontColor(Color.White)
            .backgroundColor('#33FFFFFF')
            .margin({ top: 14 })
            .enabled(!this.settled)
            .onClick(() => {
              this.settle(false, 'CANCELLED', '已取消刷脸', '');
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, top: 56, bottom: 40 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  private ensurePermission(): void {
    if (this.permissionState === PERMISSION_GRANTED) {
      return;
    }
    this.checkPermission()
      .then((granted: boolean) => {
        if (granted) {
          this.onPermissionReady(true);
          return;
        }
        this.requestPermission()
          .then((result: boolean) => {
            this.onPermissionReady(result);
          })
          .catch((error: BusinessError) => {
            this.failAndClose('PERMISSION_DENIED', `相机权限申请失败：${error.message}`);
          });
      })
      .catch((error: BusinessError) => {
        this.failAndClose('PERMISSION_DENIED', `相机权限检测失败：${error.message}`);
      });
  }

  private onPermissionReady(granted: boolean): void {
    if (granted) {
      this.permissionState = PERMISSION_GRANTED;
      this.statusText = '正在准备摄像头…';
      if (this.surfaceId.length > 0) {
        this.openCamera();
      }
      return;
    }
    this.permissionState = PERMISSION_DENIED;
    this.failAndClose('PERMISSION_DENIED', '未获得相机权限，请在系统设置中允许使用相机');
  }

  private async checkPermission(): Promise<boolean> {
    const manager = abilityAccessCtrl.createAtManager();
    const status = await manager.checkAccessToken(
      this.abilityContext.applicationInfo.uid,
      'ohos.permission.CAMERA'
    );
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async requestPermission(): Promise<boolean> {
    const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
    const manager = abilityAccessCtrl.createAtManager();
    const result = await manager.requestPermissionsFromUser(this.abilityContext, permissions);
    if (result.authResults.length === 0) {
      return false;
    }
    for (let index = 0; index < result.authResults.length; index++) {
      if (result.authResults[index] !== 0) {
        return false;
      }
    }
    return true;
  }

  private async openCamera(): Promise<void> {
    if (this.opening || this.settled || this.photoSession !== null || this.surfaceId.length === 0) {
      return;
    }
    this.opening = true;
    try {
      const manager = camera.getCameraManager(this.abilityContext);
      const device = this.pickCameraDevice(manager);
      if (device === null) {
        this.opening = false;
        this.failAndClose('UNSUPPORTED', '这台设备没有可用的摄像头');
        return;
      }
      const capability = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile = this.pickPreviewProfile(capability.previewProfiles);
      const photoProfile = this.pickPhotoProfile(capability.photoProfiles);
      if (previewProfile === null || photoProfile === null) {
        this.opening = false;
        this.failAndClose('UNSUPPORTED', '摄像头不支持实时预览拍照');
        return;
      }
      const input = manager.createCameraInput(device);
      await input.open();
      this.cameraInput = input;
      const preview = manager.createPreviewOutput(previewProfile, this.surfaceId);
      this.previewOutput = preview;
      this.applyPreviewRotation(preview);
      const photo = manager.createPhotoOutput(photoProfile);
      this.photoOutput = photo;
      const session = manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.photoSession = session;
      session.beginConfig();
      session.addInput(input);
      session.addOutput(preview);
      session.addOutput(photo);
      await session.commitConfig();
      await session.start();
      photo.on('photoAvailable', (err: BusinessError, captured: camera.Photo) => {
        this.handlePhoto(err, captured);
      });
      this.opening = false;
      this.ready = true;
      this.statusText = '请正对屏幕，保持不动';
      this.startAutoCapture();
    } catch (error) {
      const failure = error as BusinessError;
      this.opening = false;
      this.failAndClose('FAILED', `打开摄像头失败：${failure.message}`);
    }
  }

  private pickCameraDevice(manager: camera.CameraManager): camera.CameraDevice | null {
    const devices = manager.getSupportedCameras();
    if (devices.length === 0) {
      return null;
    }
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
        return devices[index];
      }
    }
    return devices[0];
  }

  private surfaceRatio(): number {
    let displayWidth = 1080;
    let displayHeight = 2340;
    try {
      const info = display.getDefaultDisplaySync();
      if (info.width > 0 && info.height > 0) {
        displayWidth = info.width;
        displayHeight = info.height;
      }
    } catch (error) {
    }
    return displayWidth / displayHeight;
  }

  private pickPreviewProfile(profiles: Array<camera.Profile>): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    const target = this.surfaceRatio();
    let best: camera.Profile = profiles[0];
    let bestScore = Number.MAX_VALUE;
    let bestArea = 0;
    for (let index = 0; index < profiles.length; index++) {
      const profile = profiles[index];
      const width = profile.size.width;
      const height = profile.size.height;
      if (width <= 0 || height <= 0) {
        continue;
      }
      const portraitRatio = width >= height ? height / width : width / height;
      const score = Math.abs(portraitRatio - target);
      const area = width * height;
      if (score < bestScore - 0.001) {
        best = profile;
        bestScore = score;
        bestArea = area;
      } else if (Math.abs(score - bestScore) <= 0.001 && area > bestArea) {
        best = profile;
        bestArea = area;
      }
    }
    return best;
  }

  private pickPhotoProfile(profiles: Array<camera.Profile>): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    let best: camera.Profile | null = null;
    let bestArea = 0;
    let fallback: camera.Profile | null = null;
    let fallbackArea = Number.MAX_VALUE;
    for (let index = 0; index < profiles.length; index++) {
      const profile = profiles[index];
      const width = profile.size.width;
      const height = profile.size.height;
      if (width <= 0 || height <= 0) {
        continue;
      }
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_JPEG) {
        continue;
      }
      const area = width * height;
      if (area <= PHOTO_AREA_LIMIT && area > bestArea) {
        best = profile;
        bestArea = area;
      }
      if (area < fallbackArea) {
        fallback = profile;
        fallbackArea = area;
      }
    }
    if (best !== null) {
      return best;
    }
    if (fallback !== null) {
      return fallback;
    }
    return profiles[0];
  }

  private applyPreviewRotation(preview: camera.PreviewOutput): void {
    try {
      const displayRotation = display.getDefaultDisplaySync().rotation;
      const rotation = preview.getPreviewRotation(displayRotation);
      preview.setPreviewRotation(rotation, false);
    } catch (error) {
      // 低版本设备由系统自动旋转预览，失败时不阻塞流程。
    }
  }

  private resolvePhotoRotation(output: camera.PhotoOutput): camera.ImageRotation {
    try {
      const displayRotation = display.getDefaultDisplaySync().rotation;
      let deviceDegree = 0;
      if (displayRotation === 1) {
        deviceDegree = 90;
      } else if (displayRotation === 2) {
        deviceDegree = 180;
      } else if (displayRotation === 3) {
        deviceDegree = 270;
      }
      return output.getPhotoRotation(deviceDegree);
    } catch (error) {
      return camera.ImageRotation.ROTATION_0;
    }
  }
  private startAutoCapture(): void {
    let delay = this.options.delayMs;
    if (!(delay > 0)) {
      delay = DEFAULT_DELAY_MS;
    }
    if (delay > MAX_DELAY_MS) {
      delay = MAX_DELAY_MS;
    }
    let remaining = Math.ceil(delay / 1000);
    this.countdownText = remaining > 0 ? `${remaining}` : '';
    if (remaining > 1) {
      this.countdownTimer = setInterval(() => {
        remaining = remaining - 1;
        if (remaining <= 0) {
          this.countdownText = '';
          this.clearCountdown();
        } else {
          this.countdownText = `${remaining}`;
        }
      }, 1000);
    }
    this.autoTimer = setTimeout(() => {
      this.autoTimer = -1;
      this.captureNow();
    }, delay);
  }

  private async captureNow(): Promise<void> {
    if (this.capturing || this.settled) {
      return;
    }
    const output = this.photoOutput;
    if (output === null || this.photoSession === null) {
      return;
    }
    this.capturing = true;
    this.countdownText = '';
    this.clearCountdown();
    if (this.autoTimer !== -1) {
      clearTimeout(this.autoTimer);
      this.autoTimer = -1;
    }
    this.statusText = '正在抓拍，请保持不动…';
    this.watchdogTimer = setTimeout(() => {
      this.watchdogTimer = -1;
      if (!this.settled) {
        this.capturing = false;
        this.failAndClose('FAILED', '抓拍超时，请重试');
      }
    }, CAPTURE_WATCHDOG_MS);
    try {
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: this.resolvePhotoRotation(output),
        mirror: false
      };
      await output.capture(setting);
    } catch (error) {
      const failure = error as BusinessError;
      this.capturing = false;
      this.failAndClose('FAILED', `抓拍失败：${failure.message}`);
    }
  }

  private handlePhoto(err: BusinessError, captured: camera.Photo): void {
    if (this.settled || !this.capturing) {
      return;
    }
    this.savePhoto(captured)
      .then((path: string) => {
        this.settle(true, '', '', path);
      })
      .catch((error: BusinessError) => {
        this.failAndClose('FAILED', `读取抓拍照片失败：${error.message}`);
      });
  }

  private async savePhoto(captured: camera.Photo): Promise<string> {
    const mainImage: image.Image = captured.main;
    const component = await mainImage.getComponent(image.ComponentType.JPEG);
    const buffer = component.byteBuffer;
    if (buffer.byteLength <= 0) {
      throw new Error('抓拍数据为空');
    }
    const path = `${this.abilityContext.cacheDir}/face_capture_${Date.now()}.jpg`;
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
    );
    try {
      fileIo.writeSync(file.fd, buffer);
    } finally {
      fileIo.closeSync(file);
    }
    if (fileIo.statSync(path).size <= 0) {
      throw new Error('抓拍照片写入失败');
    }
    try {
      await mainImage.release();
    } catch (error) {
    }
    return path;
  }

  private failAndClose(code: string, message: string): void {
    this.settle(false, code, message, '');
  }

  private settle(ok: boolean, code: string, message: string, path: string): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    this.capturing = false;
    this.ready = false;
    this.countdownText = '';
    this.clearTimers();
    const outcome: FaceCameraOutcome = { ok: ok, code: code, message: message, path: path };
    if (ok) {
      this.statusText = '抓拍成功，正在识别…';
      this.errorText = '';
    } else {
      this.statusText = message;
      this.errorText = message;
    }
    this.releaseCamera();
    this.exitTimer = setTimeout(() => {
      this.exitTimer = -1;
      FaceCameraSession.finish(outcome);
      router.back();
    }, ok ? SUCCESS_DISPLAY_MS : ERROR_DISPLAY_MS);
  }

  private clearCountdown(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private clearTimers(): void {
    this.clearCountdown();
    if (this.autoTimer !== -1) {
      clearTimeout(this.autoTimer);
      this.autoTimer = -1;
    }
    if (this.watchdogTimer !== -1) {
      clearTimeout(this.watchdogTimer);
      this.watchdogTimer = -1;
    }
  }

  private async releaseCamera(): Promise<void> {
    const session = this.photoSession;
    const preview = this.previewOutput;
    const photo = this.photoOutput;
    const input = this.cameraInput;
    this.photoSession = null;
    this.previewOutput = null;
    this.photoOutput = null;
    this.cameraInput = null;
    if (session !== null) {
      try {
        await session.stop();
      } catch (error) {
      }
      try {
        await session.release();
      } catch (error) {
      }
    }
    if (preview !== null) {
      try {
        await preview.release();
      } catch (error) {
      }
    }
    if (photo !== null) {
      try {
        await photo.release();
      } catch (error) {
      }
    }
    if (input !== null) {
      try {
        await input.close();
      } catch (error) {
      }
    }
  }
}