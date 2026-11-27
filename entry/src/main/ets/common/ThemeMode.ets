/**
 * 外观模式（跟随系统 / 明亮 / 深色）。
 *
 * 颜色本身走资源引用（resources/base|dark/element/color.json），
 * 这里只负责：
 *   1. 把用户选择持久化到 preferences；
 *   2. 调 applicationContext.setColorMode() 让系统按对应模式取资源；
 *   3. 启动时恢复上次的选择。
 */
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { WindowStyle } from './WindowStyle';

const PREFS_NAME: string = 'lockwarden_theme';
const KEY_MODE: string = 'mode';

export class ThemeMode {
  static readonly SYSTEM: string = 'system';
  static readonly LIGHT: string = 'light';
  static readonly DARK: string = 'dark';

  /** 当前模式（'system' | 'light' | 'dark'） */
  static mode: string = ThemeMode.SYSTEM;

  private static prefs: preferences.Preferences | null = null;
  private static context: common.UIAbilityContext | null = null;

  /** 启动时调用：读回上次选择并立即应用 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    ThemeMode.context = context;
    try {
      ThemeMode.prefs = await preferences.getPreferences(context, PREFS_NAME);
      const saved: string = ThemeMode.prefs.getSync(KEY_MODE, ThemeMode.SYSTEM) as string;
      ThemeMode.mode = saved.length > 0 ? saved : ThemeMode.SYSTEM;
    } catch (e) {
      ThemeMode.mode = ThemeMode.SYSTEM;
    }
    ThemeMode.apply(ThemeMode.mode);
  }

  /** 切换模式并持久化 */
  static async set(mode: string): Promise<void> {
    ThemeMode.apply(mode);
    if (ThemeMode.prefs !== null) {
      await ThemeMode.prefs.put(KEY_MODE, mode);
      await ThemeMode.prefs.flush();
    }
  }

  static label(mode: string): string {
    if (mode === ThemeMode.LIGHT) {
      return '明亮';
    }
    if (mode === ThemeMode.DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  static index(mode: string): number {
    if (mode === ThemeMode.LIGHT) {
      return 1;
    }
    if (mode === ThemeMode.DARK) {
      return 2;
    }
    return 0;
  }

  static fromIndex(index: number): string {
    if (index === 1) {
      return ThemeMode.LIGHT;
    }
    if (index === 2) {
      return ThemeMode.DARK;
    }
    return ThemeMode.SYSTEM;
  }

  private static apply(mode: string): void {
    ThemeMode.mode = mode;
    if (ThemeMode.context === null) {
      return;
    }
    const app = ThemeMode.context.getApplicationContext();
    if (mode === ThemeMode.LIGHT) {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else if (mode === ThemeMode.DARK) {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    WindowStyle.refresh(ThemeMode.isDark());
  }

  /** 当前实际生效的是不是深色（跟随系统时看系统配置） */
  static isDark(): boolean {
    if (ThemeMode.mode === ThemeMode.DARK) {
      return true;
    }
    if (ThemeMode.mode === ThemeMode.LIGHT) {
      return false;
    }
    const ctx: common.UIAbilityContext | null = ThemeMode.context;
    if (ctx === null) {
      return false;
    }
    return ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
}
