/**
 * 隐私保护：禁止截屏 / 录屏。
 *
 * 开启后调用窗口的 setWindowPrivacyMode(true)，系统层会把本应用的截屏与录屏显示为黑屏
 * （包括系统截图、控制中心录屏），保险库内容不会被截走。
 * 选择持久化在 preferences，启动时自动恢复。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WindowStyle } from './WindowStyle';

const PREFS_NAME: string = 'lockwarden_privacy';
const KEY_NO_SCREENSHOT: string = 'no_screenshot';

export class PrivacyMode {
  /** 当前是否禁止截图 */
  static enabled: boolean = false;

  private static prefs: preferences.Preferences | null = null;

  /** 启动时调用：读回上次设置并应用 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    try {
      PrivacyMode.prefs = await preferences.getPreferences(context, PREFS_NAME);
      PrivacyMode.enabled = PrivacyMode.prefs.getSync(KEY_NO_SCREENSHOT, false) as boolean;
    } catch (e) {
      PrivacyMode.enabled = false;
    }
    PrivacyMode.apply();
  }

  /** 切换并持久化 */
  static async set(enabled: boolean): Promise<void> {
    PrivacyMode.enabled = enabled;
    PrivacyMode.apply();
    if (PrivacyMode.prefs !== null) {
      try {
        await PrivacyMode.prefs.put(KEY_NO_SCREENSHOT, enabled);
        await PrivacyMode.prefs.flush();
      } catch (e) {
        // 持久化失败不影响本次开关生效
      }
    }
  }

  private static apply(): void {
    WindowStyle.applyPrivacy(PrivacyMode.enabled);
  }
}
