/**
 * 响应式宽度判定（横竖屏切换时自动刷新）。
 *
 * 之前各页面只在 aboutToAppear 里算一次宽度，横竖屏切换后不会重新判断，
 * 表现为"转屏了但布局还是老的"。这里改用 mediaquery 监听宽度断点：
 *  - 宽屏（>= 860vp）：平板横屏
 *  - 窄屏：手机、平板竖屏
 */
import { mediaquery } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { UIContext } from '@kit.ArkUI';

/** 两栏/宽屏断点（vp），与各页面内容列宽上限保持一致 */
export const WIDE_BREAKPOINT: number = 860;

export class Responsive {
  /** 高度不足时的紧凑阈值（vp）：大折叠展开、小平板横屏等 */
  static readonly COMPACT_HEIGHT: number = 760;

  /** 当前可用高度是否偏矮（需要压缩控件高度） */
  static isCompactNow(): boolean {
    const info = display.getDefaultDisplaySync();
    return info.height / info.densityPixels < Responsive.COMPACT_HEIGHT;
  }


  /** 当前是否宽屏 */
  static isWideNow(): boolean {
    const info = display.getDefaultDisplaySync();
    return info.width / info.densityPixels > WIDE_BREAKPOINT;
  }

  /**
   * 监听宽度断点变化，返回监听器（页面销毁时要 off('change')）。
   * @param uiContext 页面 UIContext（this.getUIContext()）
   * @param onChange 宽屏状态变化回调
   */
  static watchWide(uiContext: UIContext, onChange: (wide: boolean) => void): mediaquery.MediaQueryListener {
    const listener: mediaquery.MediaQueryListener =
      uiContext.getMediaQuery().matchMediaSync(`(min-width: ${WIDE_BREAKPOINT}vp)`);
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      onChange(result.matches);
    });
    return listener;
  }
}
