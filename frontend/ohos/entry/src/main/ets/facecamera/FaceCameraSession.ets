/*
 * 慧药管家 鸿蒙 A 版刷脸：Flutter 与原生相机页之间的会话桥
 * 只在同一个 UIAbility 的 JS 上下文内传递数据，不依赖其他模块。
 */

export interface FaceCameraOptions {
  mode: string;
  delayMs: number;
  hint: string;
}

export interface FaceCameraOutcome {
  ok: boolean;
  code: string;
  message: string;
  path: string;
}

export type FaceCameraCompletion = (outcome: FaceCameraOutcome) => void;

export class FaceCameraSession {
  private static completion: FaceCameraCompletion | null = null;
  private static options: FaceCameraOptions = { mode: 'login', delayMs: 2000, hint: '' };

  static begin(completion: FaceCameraCompletion, options: FaceCameraOptions): void {
    FaceCameraSession.completion = completion;
    FaceCameraSession.options = options;
  }

  static isActive(): boolean {
    return FaceCameraSession.completion !== null;
  }

  static currentOptions(): FaceCameraOptions {
    return FaceCameraSession.options;
  }

  static finish(outcome: FaceCameraOutcome): void {
    const completion = FaceCameraSession.completion;
    FaceCameraSession.completion = null;
    if (completion !== null) {
      completion(outcome);
    }
  }

  static clear(): void {
    FaceCameraSession.completion = null;
  }
}