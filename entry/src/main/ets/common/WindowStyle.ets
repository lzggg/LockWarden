/**
 * 系统栏配色。
 *
 * 默认情况下，底部导航条区域由系统按窗口背景着色，和底部 TabBar（Theme.CARD 白色）对不上，
 * 看起来就是"四个选项下面多出一条灰边"。这里把状态栏 / 导航条的颜色改成跟界面一致：
 *   - 导航条 = 卡片色（和 TabBar 同色，视觉上连成一片）
 *   - 状态栏 = 页面背景色
 * 深浅色切换时由 ThemeMode 负责再次调用 refresh()。
 */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrivacyMode } from './PrivacyMode';

export class WindowStyle {
  private static win: window.Window | null = null;
  private static ctx: common.UIAbilityContext | null = null;

  /** 窗口创建后调用一次 */
  static attach(windowStage: window.WindowStage, context: common.UIAbilityContext): void {
    WindowStyle.ctx = context;
    try {
      WindowStyle.win = windowStage.getMainWindowSync();
      // 全屏布局：让应用自己画到屏幕底部（包括导航条区域），这样 TabBar 下面不会多一条系统色带
      WindowStyle.win.setWindowLayoutFullScreen(true);
    } catch (e) {
      WindowStyle.win = null;
    }
    WindowStyle.refresh(false);
    WindowStyle.applyPrivacy(PrivacyMode.enabled);
  }

  /** 按当前深浅色重设系统栏颜色 */
  static refresh(dark: boolean): void {
    const win: window.Window | null = WindowStyle.win;
    const ctx: common.UIAbilityContext | null = WindowStyle.ctx;
    if (win === null || ctx === null) {
      return;
    }
    try {
      const card: string = WindowStyle.hex(ctx.resourceManager.getColorSync($r('app.color.app_card')));
      const background: string = WindowStyle.hex(ctx.resourceManager.getColorSync($r('app.color.app_background')));
      const fore: string = dark ? '#FFFFFF' : '#000000';
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: fore,
        navigationBarColor: '#00000000',
        navigationBarContentColor: fore
      });
    } catch (e) {
      hilog.error(0x0001, 'LockWarden', 'window bar color failed: %{public}s', (e as Error).message);
    }
  }

  /** 是否禁止截屏（由 PrivacyMode 设置，窗口就绪后调用生效） */
  static applyPrivacy(enabled: boolean): void {
    const win: window.Window | null = WindowStyle.win;
    if (win === null) {
      return;
    }
    try {
      win.setWindowPrivacyMode(enabled);
    } catch (e) {
      hilog.error(0x0001, 'LockWarden', 'privacy mode failed: %{public}s', (e as Error).message);
    }
  }

  private static hex(argb: number): string {
    const value: number = argb & 0xFFFFFF;
    return '#' + value.toString(16).padStart(6, '0').toUpperCase();
  }
}
