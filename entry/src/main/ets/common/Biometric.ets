/**
 * 生物识别（面容 / 指纹）封装。
 *
 * 用系统 @kit.UserAuthenticationKit 拉起统一认证弹窗。
 *
 * 需要的权限：ohos.permission.ACCESS_BIOMETRIC（system_grant/normal，声明即授予）。
 * 少了这个权限，getAvailableStatus / getEnrolledState / start 全部会失败，
 * 表现为"开关永远禁用、点了没反应"。
 *
 * 可用性判断走 getAvailableStatus（不支持时抛 12500005/12500006）
 * 再叠加 getEnrolledState（未录入时 credentialCount 为 0），
 * 并把失败原因带回去，界面上能直接显示"是没录入还是硬件不支持"。
 */
import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Bytes } from './CryptoUtils';

export interface BiometricSupport {
  available: boolean;
  face: boolean;
  fingerprint: boolean;
  /** 不可用时的原因，可直接展示 */
  reason: string;
}

/** 生成一个一次性挑战值（仅用于绑定本次认证，不参与密钥派生） */
function randomChallenge(): Uint8Array {
  // 认证挑战值使用系统密码学随机源，避免可预测的挑战
  return Bytes.random(16);
}

/**
 * 返回空串表示该类型可用，否则返回可直接展示给用户的原因。
 * 注意：这里不能把系统错误码暴露给用户，按错误码翻译成中文说明：
 *   12500005 / 12500006 → 设备不支持（认证类型或安全等级不支持）
 *   12500010           → 未录入（该类型凭证还没录入）
 *   12500009           → 已锁定
 *   12500007           → 正忙
 */
function probe(type: userAuth.UserAuthType, label: string): string {
  try {
    userAuth.getAvailableStatus(type, userAuth.AuthTrustLevel.ATL2);
  } catch (e) {
    const err: BusinessError = e as BusinessError;
    if (err.code === 12500010) {
      // 未录入凭证：设备可能压根没有该能力，也可能只是没录入
      return `设备不支持或未录入${label}`;
    }
    if (err.code === 12500009) {
      return `${label}已锁定，请稍后再试`;
    }
    if (err.code === 12500007) {
      return `${label}正忙，请稍后再试`;
    }
    // 12500005 认证类型不支持、12500006 安全等级不支持，以及其它无法识别的错误，
    // 对用户而言都是"这台设备用不了这项功能"
    return `设备不支持${label}`;
  }
  try {
    const state: userAuth.EnrolledState = userAuth.getEnrolledState(type);
    if (state.credentialCount <= 0) {
      return `未录入${label}`;
    }
  } catch (e) {
    return `未录入${label}`;
  }
  return '';
}

export class Biometric {
  /** 认证面板需要租户上下文才能显示，由入口页在启动时注入 */
  private static uiContext: common.UIAbilityContext | null = null;
  /** 最近一次认证失败的原因，便于界面展示/排查 */
  static lastError: string = '';

  static setContext(context: common.UIAbilityContext): void {
    Biometric.uiContext = context;
  }

  static fingerprintAvailable(): boolean {
    return Biometric.availableFor(userAuth.UserAuthType.FINGERPRINT);
  }

  static faceAvailable(): boolean {
    return Biometric.availableFor(userAuth.UserAuthType.FACE);
  }

  static fingerprintReason(): string {
    return Biometric.reasonFor(userAuth.UserAuthType.FINGERPRINT);
  }

  static faceReason(): string {
    return Biometric.reasonFor(userAuth.UserAuthType.FACE);
  }

  static authenticateFingerprint(title: string): Promise<boolean> {
    return Biometric.authenticate(title, userAuth.UserAuthType.FINGERPRINT);
  }

  static authenticateFace(title: string): Promise<boolean> {
    return Biometric.authenticate(title, userAuth.UserAuthType.FACE);
  }
  /** 查询本机可用的生物识别类型与不可用原因 */
  static query(): BiometricSupport {
    const fingerprintReason: string = probe(userAuth.UserAuthType.FINGERPRINT, '指纹');
    const faceReason: string = probe(userAuth.UserAuthType.FACE, '面容');
    const fingerprint: boolean = fingerprintReason.length === 0;
    const face: boolean = faceReason.length === 0;
    const available: boolean = face || fingerprint;
    let reason: string = '';
    if (!available) {
      reason = fingerprintReason.length > 0 ? fingerprintReason : faceReason;
    }
    const support: BiometricSupport = {
      available: available,
      face: face,
      fingerprint: fingerprint,
      reason: reason
    };
    return support;
  }

  /** 指定类型是否可用 */
  static availableFor(authType: userAuth.UserAuthType): boolean {
    const label: string = authType === userAuth.UserAuthType.FACE ? '面容' : '指纹';
    return probe(authType, label).length === 0;
  }

  /** 指定类型不可用的原因（可用时返回空串） */
  static reasonFor(authType: userAuth.UserAuthType): string {
    const label: string = authType === userAuth.UserAuthType.FACE ? '面容' : '指纹';
    return probe(authType, label);
  }

  /** 拉起系统认证弹窗；通过返回 true */
  static authenticate(title: string, authType: userAuth.UserAuthType): Promise<boolean> {
    Biometric.lastError = '';
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      try {
        if (!Biometric.availableFor(authType)) {
          Biometric.lastError = Biometric.reasonFor(authType);
          resolve(false);
          return;
        }
        const authParam: userAuth.AuthParam = {
          challenge: randomChallenge(),
          authType: [authType],
          authTrustLevel: userAuth.AuthTrustLevel.ATL2
        };
        const widget: userAuth.WidgetParam = { title: title };
        if (Biometric.uiContext !== null) {
          widget.uiContext = Biometric.uiContext;
        }
        const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widget);
        let settled: boolean = false;
        // IAuthCallback 是"带 onResult 方法的接口"，不是函数类型，必须传对象
        const callback: userAuth.IAuthCallback = {
          onResult: (result: userAuth.UserAuthResult): void => {
            if (settled) {
              return;
            }
            settled = true;
            const code: number = result.result;
            if (code !== userAuth.UserAuthResultCode.SUCCESS) {
              if (code === userAuth.UserAuthResultCode.CANCELED) {
                Biometric.lastError = '已取消验证';
              } else if (code === userAuth.UserAuthResultCode.FAIL) {
                Biometric.lastError = '验证未通过';
              } else if (code === userAuth.UserAuthResultCode.LOCKED) {
                Biometric.lastError = '尝试次数过多，请稍后再试';
              } else {
                Biometric.lastError = '验证未通过';
              }
            }
            resolve(code === userAuth.UserAuthResultCode.SUCCESS);
          }
        };
        instance.on('result', callback);
        instance.start();
      } catch (e) {
        Biometric.lastError = '无法启动验证，请改用主密码';
        resolve(false);
      }
    });
  }
}
